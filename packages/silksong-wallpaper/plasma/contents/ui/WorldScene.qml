/*
 * What one screen sees of the aquarium (tools/world.py). Plain QtQuick, so
 * tools/preview.qml can lay several of these side by side without Plasma.
 */
import QtQuick
import Qt.labs.folderlistmodel

import "world.js" as World
import "daylight.js" as Daylight
import "life.js" as Life
import "reveal.js" as Reveal

Item {
    id: root

    required property var screens // Qt.application.screens, or stand-ins with the same fields
    required property string screenName
    required property url dataDir
    property real gapMm: 15
    property real latitude: 48.85
    property real longitude: 2.35
    property bool debug: false

    // Seconds since the epoch. Driven by the wall clock (shifted by timeOffset, to try another
    // time of day) unless live is off.
    property bool live: true
    property real timeOffset: 0
    property real time: Date.now() / 1000 + timeOffset

    readonly property url worldDir: dataDir + "/world"
    readonly property var world: worldData.item?.world ?? null
    readonly property var clips: sprites.item?.clips ?? null
    readonly property real unitMm: world ? world.unitMm : 10

    // A file of the world, at its build's URL (a new build's images are new images to the engine).
    // Each source reads the build here, in its own binding: a property of its own would still hold
    // the last build (or none) while the Repeaters make their Images for a new world, and each file
    // would be decoded twice.
    function url(file) {
        return world ? worldDir + "/" + file + "?v=" + world.build : "";
    }
    // One of its big images (the tiles, the air, the sheets: what a screen waits for under black)
    // from its QOI twin (tools/derive.py), the same pixels read 2-4 times faster than the PNG:
    // where Qt reads QOI (KDE's image formats, tried at once on a one-pixel image) and the twins
    // were made for this build; else, or if the twin can't be read after all (png, Asset), from
    // the PNG. Nothing until the probe has answered, rather than the PNG first and then the twin.
    function big(file, png) {
        const probed = qoiProbe.status === Image.Ready || qoiProbe.status === Image.Error;
        if (!world || !probed) {
            return "";
        }
        const qoi = qoiProbe.status === Image.Ready && !png ? derivedOf(world.build)?.qoi : null;
        return url(qoi?.[file] ? file.slice(0, -4) + ".qoi" : file);
    }
    // What tools/derive.py made for a build (its Derived.qml), read the first time one of its
    // images asks, at once: a Loader of its own could still hold the last build's while a new
    // world's images are made. None if it was made for another build, or there's none.
    readonly property var derived: ({}) // by build, filled in as they're read
    function derivedOf(build) {
        if (!(build in derived)) {
            const list = Qt.createComponent(worldDir + "/Derived.qml?v=" + build);
            const made = list.status === Component.Ready ? list.createObject(null) : null;
            derived[build] = made?.derived.build === build ? made.derived : null;
            made?.destroy();
        }
        return derived[build];
    }
    // This screen's own view of the layers (tools/derive.py): the texels it draws of each, already
    // scaled and cut to what they hold, as pieces drawn as they are. Only where one was made for
    // this world and this very screen, its place in the layout and its size; else null, and the
    // tiles (another desk, another gap between the screens). Read in each binding that uses it, as
    // the build in url(): a property of its own could still say none while a new world's images
    // are made, and the tiles would be asked for first.
    function viewHere() {
        const views = world ? derivedOf(world.build)?.views ?? none : none;
        return views.find(v => Math.abs(v.x - me.x) < 1e-6 && Math.abs(v.w - me.w) < 1e-6
            && v.px[0] === width && v.px[1] === height) ?? null;
    }
    // The folder where tools/derive.py made the sheets at this screen's density, each at the size
    // it's asked for here (sheetScale), scaled by Qt itself, to be read as it is; else "". Read in
    // each sheet's binding, as viewHere().
    function sheetSet() {
        const sets = world ? derivedOf(world.build)?.sheetSets ?? {} : {};
        return Object.keys(sets).find(folder => Math.abs(sets[folder] - pxPerUnit) < 1e-6) ?? "";
    }

    readonly property var layout: World.layout(screens, gapMm)
    readonly property var me: layout.screens[screenName] ?? { x: 0, y: 0, w: width / 4, h: height / 4 }
    readonly property real pxPerMm: width / me.w
    readonly property real pxPerUnit: pxPerMm * unitMm

    // One empty list for whatever has nothing to show, so that it isn't a new one on every tick
    // (each new list would set off everything bound to it).
    readonly property var none: []

    readonly property var hornet: clips && world ? Life.hornetAt(world, clips, time) : null
    // The zones she's in, by share: her colours and her light blend between them (the game lerps
    // its scene colours, SceneColorManager, rather than switching them). Only where she's drawn.
    readonly property var hornetZones: hornetHere ? World.zoneWeights(world, hornet.x, hornet.y, 2.0) : none
    readonly property var hornetZone: hornetZones.length ? hornetZones[0].zone : null
    readonly property var hornetZone2: hornetZones.length > 1 ? hornetZones[1].zone : null
    readonly property real hornetBlend: hornetZones.length > 1 ? hornetZones[1].weight / (hornetZones[0].weight + hornetZones[1].weight) : 0
    readonly property bool hornetHere: hornet !== null
        && hornet.x * unitMm > me.x - 120 && hornet.x * unitMm < me.x + me.w + 120
    // Her pose where she's drawn, else null, so that her sprite isn't worked out again on every
    // tick on the screens she isn't on; her feet, for the grass and the bells she walks into.
    readonly property var shownHornet: hornetHere ? hornet : null
    readonly property real heroFeetY: hornetHere ? hornet.y - world.heroFeet : -1e6
    // The daylight and the clock's hands only change by the second (lightingAt reads the time to
    // the second), so they're worked out once a second rather than on every tick.
    readonly property real wholeSecond: Math.floor(time)
    readonly property var daylight: Daylight.lightingAt(new Date(wholeSecond * 1000), latitude, longitude)

    function toX(xMm) {
        return (xMm - me.x) * pxPerMm;
    }
    function toY(yMm) {
        return height - (yMm - me.y) * pxPerMm;
    }

    // One clock per screen. By default (everyFrame) it ticks on every frame its window draws (each
    // tick asks for the next frame, and the frame brings the next tick), so that everything moves
    // as smoothly as the game moves it: the fast falling drops would jump at any slower pace.
    // Paced (Motion, in the settings), it only ticks when something it shows changes, so that each
    // change is drawn once, on time, for less work. While Hornet moves where she's seen, or grass
    // she walked into springs back, on every frame. Otherwise on a timer, set for just after the
    // first change to come: her clip's next cell, the Bell Beast's next frame, a jingling floor
    // bell's, or a step of what moves on its own (the water, the plants, the particles, the small
    // life, the gears) at the pace it needs: the water 30 times a second, plants and particles 15,
    // on the grass's own frames (the game snaps it to 15 a second), the clock's gears 10, else 4
    // (to notice her coming and move the daylight). Where she's seen at rest, nearHz if that's
    // more: from 60, every frame. On the Bell Beast's screen, 12 with its frames, its animations'
    // rate (at 15 its frames would last one tick, then two: it would look hurried). Not a
    // FrameAnimation: while one runs with more than one window shown, every timer of the process
    // (Plasma's too) is rounded to a 16 ms tick of an animation clock that runs 4% fast.
    property bool everyFrame: true // Motion 0; paced otherwise
    // Paced, where Hornet rests: Motion 1 is 60, 2 is 30, 3 is 0 (the screen's own pace).
    property int nearHz: 30
    readonly property bool showsClock: clock !== null
        && clock.x * unitMm > me.x - 30 && clock.x * unitMm < me.x + me.w + 30
    readonly property bool showsAmbient: (swayHere.length > 0 || showsParticles || airHere.length > 0 || crittersHere.length > 0)
        && GraphicsInfo.api !== GraphicsInfo.Software
    readonly property real ambientRate: showsWater ? 30 : showsBeast ? 12 : showsAmbient ? 15 : showsClock ? 10 : 4 // a second
    // Whether anything of Hornet's is drawn on this screen: her sprite (4.1 units either side of
    // her), her light (7.3) or her needle's silk, from her hand to the needle.
    readonly property bool hornetSeen: shownHornet !== null && reaches(shownHornet)
    function reaches(h) {
        const lo = h.thread ? Math.min(h.x, h.thread[0], h.thread[2]) : h.x;
        const hi = h.thread ? Math.max(h.x, h.thread[0], h.thread[2]) : h.x;
        return (hi + 8.5) * unitMm > me.x && (lo - 8.5) * unitMm < me.x + me.w;
    }

    // It runs while the scene is live and shown (Plasma only hides the desktops of the other
    // activities), not paused and revealed. It parks while its window draws nothing, the screen
    // off or the window covered (the compositor stops asking for frames, and Qt stops drawing):
    // seen as a frame it asked for still not drawn at the third round of its watchdog (rounds,
    // not times, so that the wall clock moving can't fool it). Either way it starts again from the
    // current moment, in time for the window's first frame back.
    property bool paused: false
    readonly property bool running: live && !paused && visible && revealed // visible: false under a hidden parent too
    property bool continuous: false // ticking on the window's frames rather than on the timer
    property bool parked: false
    property bool asked: false // a frame it asked for and the window hasn't drawn yet
    property int waited: 0 // the watchdog's rounds it has been waited for
    property real nextAt: 0 // when the timer is set for, on the shifted clock
    property real wokeAt: -1e9 // when it last started again
    property real pushUntil: -1e9 // when the grass Hornet walked into is still again
    property var bellItems: [] // the floor bells' pieces, whose frames it keeps time for

    function tick(at) {
        if (!running || parked) {
            return;
        }
        const now = at ?? Date.now() / 1000 + timeOffset;
        if (at === undefined && Math.abs(now - time) > 2) {
            // The machine slept, or the clock was set (its ticks are never more than a second
            // apart): it starts again from now as after a pause, rather than draw the new moment
            // without its sheets, or her jump there as a move among the floor bells.
            continuous = false;
            wake.stop();
            resume();
            return;
        }
        if (now < time - 1) {
            // The clock was set back: carry on from now as after a pause (wokeAt), rather than
            // wait for what was to come (grass springing back, her moves among the bells, their
            // shakes).
            wokeAt = now;
            nextAt = now;
            pushUntil = -1e9;
            hornetMovedAt = -1e9;
            for (let i = 0; i < bellItems.length; i++) {
                bellItems[i].startedAt = bellItems[i].endsAt = -1e9;
            }
        }
        const due = at === undefined && !continuous; // the timer's
        if (due && now < nextAt - 0.02) {
            arm(); // early: while anything animates, timers ride the animation clock
            return;
        }
        // On the timer, the very moment it was set for, a few ms either way: what changes then is
        // drawn on its frame, however late or early the timer fires.
        time = due && Math.abs(now - nextAt) < 0.02 ? nextAt : now;
        for (let i = 0; i < bellItems.length; i++) {
            bellItems[i].stir();
        }
        asked = true;
        root.Window.window?.update();
        schedule();
    }
    function schedule() {
        const t = time;
        const hornetNext = hornetSeen ? Life.hornetChangesAt(world, clips, t) : Infinity;
        continuous = (everyFrame && GraphicsInfo.api !== GraphicsInfo.Software) || t < pushUntil
            || (hornetSeen && (nearHz >= 60 || hornetNext <= t));
        if (continuous) {
            wake.stop();
            return;
        }
        // The steps of what moves on its own fall on a grid, so that they're even: at 15 a second
        // on the grass's frames, which change half way between fifteenths (it's rounded), at 30 on
        // and between those. On the Bell Beast's screen they keep to its frames: a twelfth of a
        // second after the last tick, or with its next frame if that comes first.
        const beastNext = showsBeast ? Life.beastNext(world, clips, t) : Infinity;
        const rate = hornetSeen && nearHz > ambientRate ? nearHz : ambientRate;
        const phase = rate === 15 ? 0.5 : 0;
        const step = showsBeast && rate === 12 ? Math.min(t + 1 / 12, beastNext) : (Math.floor(t * rate - phase) + 1 + phase) / rate;
        const moments = [step, hornetNext, beastNext];
        if (hornetMoving) {
            moments.push(hornetMovedAt + 0.15);
        }
        for (let i = 0; i < bellItems.length; i++) {
            const bell = bellItems[i];
            if (t < bell.endsAt) {
                moments.push(bell.startedAt + (Math.floor((t - bell.startedAt) * bell.a.fps + 1e-6) + 1) / bell.a.fps, bell.endsAt);
            }
        }
        // What comes within 12 ms of the first is drawn with it, at the last of them.
        const first = Math.min.apply(null, moments);
        let next = first;
        for (let i = 0; i < moments.length; i++) {
            if (moments[i] <= first + 0.012) {
                next = Math.max(next, moments[i]);
            }
        }
        nextAt = Math.max(next, t + 0.001) + 1e-4; // just past it, whatever the rounding
        arm();
    }
    function arm() {
        wake.interval = Math.min(1000, Math.max(1, Math.round((nextAt - Date.now() / 1000 - timeOffset) * 1000)));
        wake.restart();
    }
    // Starting again, or for the first time: straight to the current moment. Her jump to where she
    // is now isn't a move among the floor bells, nor a walk into the grass (wokeAt). Started again
    // after a while, what it shows now may need sheets it let go or never had (her clips of a
    // minute later, a screen she has come to): it asks for those first (resumeFrom) and holds its
    // last frame until they're in, 300 ms at most, rather than draw her missing meanwhile. Not
    // before it has faded in: it then waited for those of its first seconds.
    property real resumeFrom: NaN // while it holds: the moment it starts from
    function resume() {
        const now = Date.now() / 1000 + timeOffset;
        parked = false;
        waited = 0;
        if (isNaN(resumeFrom) && lookaheadOn && !hasSheetsAt(now)) {
            // Asking may be enough: a sheet another screen has decoded at the same size comes
            // back at once, before there is a hold for it to end.
            resumeFrom = now;
            if (!hasSheetsAt(now)) {
                hold.start();
                return;
            }
        }
        hold.stop();
        wokeAt = now;
        tick(now);
        resumeFrom = NaN; // once the time has caught up: the look-ahead doesn't step back
    }
    // Whether it has the sheets of what it draws at t: Hornet's clip where she's drawn (hornetHere)
    // and her needle's, the Bell Beast's (the small life's are always kept).
    function hasSheetsAt(t) {
        if (!world || !clips) {
            return true;
        }
        const h = Life.hornetAt(world, clips, t);
        const want = [];
        if (h && h.x * unitMm > me.x - 120 && h.x * unitMm < me.x + me.w + 120) {
            want.push(h.clip);
            if (h.needle) {
                want.push("Harpoon Needle");
            }
        }
        if (showsBeast) {
            want.push(Life.beastAt(world, clips, t)?.clip);
        }
        return want.every(n => !clips[n] || sheets[n] !== undefined);
    }
    Timer {
        id: hold
        interval: 300
        onTriggered: root.resume()
    }
    onSheetsChanged: if (hold.running && hasSheetsAt(Date.now() / 1000 + timeOffset)) resume()
    onRunningChanged: {
        if (running) {
            resume();
        } else {
            wake.stop();
            hold.stop();
            resumeFrom = NaN;
            continuous = false;
        }
    }
    Timer {
        id: wake
        onTriggered: root.tick()
        Component.onCompleted: {
            if (root.running) {
                root.resume();
            }
        }
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.running && !root.parked
        onTriggered: {
            if (root.asked && ++root.waited > 2) {
                root.parked = true;
                root.continuous = false;
                wake.stop();
            }
        }
    }
    Connections {
        target: root.Window.window

        function onFrameSwapped() {
            root.asked = false;
            root.waited = 0;
            if (root.parked && root.running) {
                root.resume(); // the frame it waited for, drawn late (the GPU held up)
            } else if (root.continuous && root.running) {
                root.tick();
            }
        }
    }
    // Drawing again: afterAnimating comes as the window is about to take its frame (before it is
    // synchronised), so the frame shows the current moment rather than the one it parked at.
    Connections {
        target: root.Window.window
        enabled: root.parked

        function onAfterAnimating() {
            if (root.running) {
                root.resume();
            }
        }
    }

    // The world and Hornet's clips, reloaded whenever tools/world.py or extract.py write new
    // ones: each version gets its own URL, as the QML engine keeps what it loaded by URL for as
    // long as the process lives (plasmashell runs for days). Watched only where asked (watchFiles:
    // on the desktop, as the lock screen lives for minutes), each watcher being a thread and a scan
    // of its folder. There a file is only asked for once its watcher has seen it: the engine also
    // remembers, for as long, a file it was asked for and didn't find (Qt 6.11 keeps its folder's
    // listing), and would never read it once there (a first install).
    property bool watchFiles: false
    property real worldStamp: 0 // where watched, the version of each to read (its time), 0 for none yet
    property real spritesStamp: 0
    component Watch: FolderListModel {
        required property string file
        property real stamp: 0

        function update() {
            const t = count > 0 ? get(0, "fileModified").getTime() : 0;
            if (t > 0) {
                stamp = t; // the same time again changes nothing
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
    Loader {
        active: root.watchFiles

        sourceComponent: Item {
            Watch {
                folder: root.worldDir
                file: "World.qml"
                onStampChanged: root.worldStamp = stamp
            }
            Watch {
                folder: root.dataDir
                file: "Sprites.qml"
                onStampChanged: root.spritesStamp = stamp
            }
        }
    }
    Loader {
        id: sprites
        source: root.watchFiles && root.spritesStamp === 0 ? "" : root.dataDir + "/Sprites.qml?v=" + root.spritesStamp
    }
    Loader {
        id: worldData
        source: root.watchFiles && root.worldStamp === 0 ? "" : root.worldDir + "/World.qml?v=" + root.worldStamp
    }
    // Whether Qt reads QOI (big()). Below the world's Loader: an item's children are completed last
    // to first, so the answer is in as the world is read and its images are made, rather than
    // holding them back past the day's plan.
    Image {
        id: qoiProbe
        visible: false
        source: "probe.qoi"
    }

    // The screen stays black until it has everything it shows, then fades in once, rather than
    // piece by piece, with the other screens (reveal.js); its clock starts then. What loads in the
    // background (the tiles, the air, the sheets) keeps count of itself (Asset), a file that fails
    // counting as in. Revealed a turn of the event loop later, in case something is asked for
    // meanwhile; whatever is still missing after 4 seconds, revealed anyway.
    property int pending: 0
    property bool revealed: false
    readonly property bool settled: world !== null && clips !== null && pending === 0 && !moved.running
    function reveal() {
        if (settled) {
            Reveal.settled();
        }
    }
    onSettledChanged: if (settled && !revealed) Qt.callLater(reveal)
    Component.onDestruction: {
        Reveal.leave(root);
        Life.leave();
    }
    Timer {
        interval: 4000
        running: !root.revealed
        onTriggered: {
            root.revealed = true;
            Reveal.settled(); // the screens that were waiting for this one
        }
    }
    // Black again at once whenever it must load anew once shown: a new world, or a new place or
    // size for the screen (a screen plugged in or taken away, another gap between them), after
    // which every tile and sheet is loaded again at its new size. Those come one after the other
    // as a screen is plugged in: it waits until they have stayed put a moment. Not as it's made: a
    // timer started then only starts counting at the event loop's next turn, once every screen is
    // made, and would hold back the first reveal.
    function conceal() {
        revealed = false;
        lookaheadOn = false;
        firstAt = Date.now() / 1000 + timeOffset;
        Qt.callLater(reveal); // in case nothing is loaded anew (the same files)
    }
    onWorldChanged: if (revealed) conceal()
    property bool everRevealed: revealed
    onRevealedChanged: everRevealed = true // whichever way it changes, it has been revealed
    readonly property string placing: [me.x, me.w, width, height, pxPerUnit].join()
    onPlacingChanged: {
        if (everRevealed) {
            conceal();
            moved.restart();
        }
    }
    Timer {
        id: moved
        interval: 300
    }

    // One of the world's big images (big()), loaded in the background and counted in pending while
    // it loads. If its twin can't be read, that image alone reads its PNG instead (png): something
    // an image read at once couldn't do, as it fails within the binding that gave it its source.
    // Given its file, the width to decode it at and what to keep of it together (req) rather than
    // as source, sourceSize and sourceClipRect, it sets the width and the part first: a change of
    // them and the file then decodes it once, at its new size.
    component Asset: Image {
        property var req // { url, width, clip: the part to keep, in texels once scaled, if not all }
        property bool png: false
        property bool counted: false
        function track() {
            const loading = status === Image.Loading;
            if (loading !== counted) {
                counted = loading;
                root.pending += loading ? 1 : -1;
            }
        }

        onReqChanged: {
            sourceSize.width = req.width;
            if (req.clip) {
                sourceClipRect = req.clip;
            }
            source = req.url;
        }
        asynchronous: true
        onStatusChanged: {
            if (status === Image.Error) {
                png = true; // if that was its twin, its PNG is loading now
            }
            track();
        }
        Component.onCompleted: track()
        Component.onDestruction: if (counted) root.pending -= 1
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // One baked layer: this screen's own view of it where there's one (viewHere()), its pieces
    // drawn as they are, else the world's tiles (World.tilePlace), of the rows that hold anything
    // only where Derived.qml lists them. The same texels, at the same places, either way.
    component Layer: Item {
        id: layer
        required property string name
        property bool active: true // nothing of it is loaded while false
        anchors.fill: parent

        Repeater {
            model: layer.active ? root.viewHere()?.layers[layer.name] ?? root.none : root.none

            Asset {
                required property var modelData

                req: ({ url: root.big(modelData.file, png), width: 0 })
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
                cache: false
                smooth: true
            }
        }

        Repeater {
            model: layer.active && root.world && !root.viewHere() ? root.world.layers[layer.name] ?? root.none : root.none

            Asset {
                required property var modelData
                readonly property var place: World.tilePlace(root.world, modelData,
                    root.derivedOf(root.world.build)?.tiles?.[modelData.file]?.rows ?? null, root.me, root.width, root.height)

                visible: place !== null
                req: ({ url: place ? root.big(modelData.file, png) : "", width: place?.fw ?? 0,
                        clip: place ? Qt.rect(place.clip[0], place.clip[1], place.clip[2], place.clip[3]) : undefined })
                x: place?.x ?? 0
                y: place?.y ?? 0
                width: place?.width ?? 0
                height: place?.height ?? 0
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
    readonly property real ambientTime: time % 3600 // the shaders work in single precision
    // The time a plant snapped to `fps` frames a second shows, rounded in single precision as
    // sway.vert rounds it: fed this, it's drawn the same but only set again when its frame changes.
    function swayClock(fps) {
        return Math.floor(Math.fround(Math.fround(Math.fround(ambientTime) * fps) + 0.5)) / fps;
    }
    readonly property real swayClock15: swayClock(15) // one for all the plants at 15, the game's usual rate

    // The air (tools/world.py AIR): light shafts that follow the daylight, mist and haze drifting
    // slowly sideways, all of it breathing; drawn behind the rock (back) or in front of everything
    // under the veil (front).
    readonly property var airHere: (world?.air ?? []).filter(a => (a.x + a.w + 2) * unitMm > me.x && (a.x - 2) * unitMm < me.x + me.w)
    readonly property real sun: Math.max(0.12, 1 - daylight.lights) // shafts fade at night, to a glimmer
    component Air: Repeater {
        id: air
        required property string group
        model: root.airHere.filter(a => a.layer === air.group)

        Asset {
            required property var modelData
            readonly property var a: modelData
            // What doesn't drift (the shafts) doesn't read the time, so it isn't placed again on
            // every tick.
            x: a.drift[0] === 0 ? root.toX(a.x * root.unitMm)
                : root.toX((a.x + a.drift[0] * Math.sin(2 * Math.PI * root.ambientTime / a.drift[1] + a.phase * 1.7)) * root.unitMm)
            y: root.toY((a.y + a.h) * root.unitMm)
            width: a.w * root.pxPerUnit
            height: a.h * root.pxPerUnit
            source: root.big(a.file, png)
            opacity: (1 + a.breathe[0] * Math.sin(2 * Math.PI * root.ambientTime / a.breathe[1] + a.phase))
                / (1 + a.breathe[0]) * (a.kind === "shaft" ? root.sun : 1)
            smooth: true
        }
    }

    // An AnimationCurve's value at t: keys [time, value, in slope, out slope], Hermite between them.
    // Read by index, not destructured: in the QML engine each destructuring allocates an iterator,
    // and a bent plant asks on every tick.
    function curveAt(keys, t) {
        if (t <= keys[0][0])
            return keys[0][1];
        for (let i = 1; i < keys.length; i++) {
            const t0 = keys[i - 1][0], v0 = keys[i - 1][1], out0 = keys[i - 1][3];
            const t1 = keys[i][0], v1 = keys[i][1], in1 = keys[i][2];
            if (t <= t1) {
                const d = t1 - t0, u = (t - t0) / d, u2 = u * u, u3 = u2 * u;
                return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * d * out0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * d * in1;
            }
        }
        return keys[keys.length - 1][1];
    }

    // Read at once, not in the background (Asset), where it took 8 MB more of GPU memory in each
    // window (Qt 6.11): its twin, if it can't be read, isn't made up for by its PNG.
    Image {
        id: swayAtlas
        visible: false
        source: root.sway ? root.big(root.sway.atlas) : ""
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
            readonly property bool touched: react !== null && root.hornetHere
                && Math.abs(root.hornet.x - modelData.x - modelData.w / 2) < modelData.w / 2
                && root.heroFeetY > rootAt - 0.3 && root.heroFeetY < rootAt + modelData.h * 0.7
            property real touchedAt: -1e9
            property real way: 1
            onTouchedChanged: {
                if (touched && root.time > root.wokeAt) {
                    touchedAt = root.time;
                    way = root.hornet.facingRight ? 1 : -1;
                    root.pushUntil = Math.max(root.pushUntil, touchedAt + react.length);
                }
            }
            readonly property real push: react && root.time - touchedAt < react.length
                ? react.amount * way * root.curveAt(react.keys, (root.time - touchedAt) / react.length) : 0

            // Without an amount or a wave it can't move: its time is never set again.
            readonly property bool still: modelData.amount === 0 || modelData.mags.every(m => m === 0)

            ShaderEffect {
                readonly property real time: piece.still ? 0
                    : piece.modelData.fps === 15 ? root.swayClock15
                    : piece.modelData.fps > 0 ? root.swayClock(piece.modelData.fps)
                    : root.ambientTime
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
    // backdrop behind her, never the rock: at night it grows a little stronger under the veil.
    component HeroLight: Image {
        required property int index // its place in hornetZones: the strongest first, drawn under the next
        readonly property var share: root.hornetZones[index] ?? null // { zone, weight }
        readonly property var info: share ? share.zone.light ?? null : null
        visible: root.hornetHere && info !== null
        opacity: info ? share.weight * Math.min(0.7, info.strength * (1 + root.daylight.lights * 0.2)) : 0
        source: info ? root.url(info.file) : ""
        x: info ? root.toX((root.hornet.x + info.left) * root.unitMm) : 0
        y: info ? root.toY((root.hornet.y + info.bottom + info.height) * root.unitMm) : 0
        width: info ? info.width * root.pxPerUnit : 0
        height: info ? info.height * root.pxPerUnit : 0
        smooth: true
    }

    Layer {
        name: "back"
    }

    // A light for each zone she can be in at once (zoneWeights can give them all), taking its share
    // by its place: a model of the shares themselves would make the lights again on every tick
    // while she crosses from one zone to the next.
    Repeater {
        model: root.world?.zones.length ?? 0

        HeroLight {}
    }

    Air {
        group: "back"
    }

    // Particle systems from the game (tools/world.py place_particles): the rooms' own (Verdania's
    // fireflies), motes, drips, smoke and falling dust placed in the world, the dust in the light
    // shafts. One item per emitter, its particles' quads on a grid that shaders/particle.vert
    // moves along their lives; behind the rock (back) or in front of everything (front).
    component Emitters: Repeater {
        id: emitters
        required property string group
        model: root.world?.particles?.filter(p => (p.layer ?? "back") === emitters.group
            && (p.area[0] + p.area[2]) * root.unitMm > root.me.x && p.area[0] * root.unitMm < root.me.x + root.me.w) ?? []

        ShaderEffect {
            id: emitter
            required property var modelData
            readonly property var p: modelData
            readonly property real time: root.ambientTime
            readonly property real slots: p.slots
            readonly property real pxPerUnit: root.pxPerUnit
            readonly property vector4d area: Qt.vector4d(p.area[0], p.area[1], p.area[2], p.area[3])
            readonly property vector4d centre: Qt.vector4d(p.x, p.y, ({ circle: 0, box: 1, edge: 2 })[p.shape], p.thickness)
            readonly property vector4d axes: Qt.vector4d(p.axes[0], p.axes[1], p.axes[2], p.axes[3])
            readonly property vector4d shapeMore: Qt.vector4d(p.arc * Math.PI / 180, p.up[0], p.up[1], 0)
            readonly property vector4d lifeSize: Qt.vector4d(p.life[0], p.life[1], p.size[0], p.size[1])
            readonly property vector4d sizeMore: Qt.vector4d(p.sizeRange[0], p.sizeRange[1], 0, 0)
            readonly property vector4d sizeT: Qt.vector4d(p.sizeKeys[0][0], p.sizeKeys[1][0], p.sizeKeys[2][0], p.sizeKeys[3][0])
            readonly property vector4d sizeV: Qt.vector4d(p.sizeKeys[0][1], p.sizeKeys[1][1], p.sizeKeys[2][1], p.sizeKeys[3][1])
            readonly property vector4d speed: Qt.vector4d(p.speed[0], p.speed[1], 0, 0)
            readonly property vector4d velocity: Qt.vector4d(p.velocity[0], p.velocity[1], p.velocity[2], p.velocity[3])
            readonly property vector4d force: Qt.vector4d(p.force[0], p.force[1], p.force[2], p.force[3])
            readonly property vector4d spin: Qt.vector4d(p.spin[0], p.spin[1], p.rotation[0], p.rotation[1])
            readonly property vector4d misc: Qt.vector4d(p.alpha, p.gravity, p.additive ? 1 : 0, 0)
            readonly property vector4d tint: Qt.vector4d(p.colour[0], p.colour[1], p.colour[2], 1)
            readonly property vector4d colourT: Qt.vector4d(p.colourKeys[0][0], p.colourKeys[1][0], p.colourKeys[2][0], p.colourKeys[3][0])
            readonly property vector4d colour0: Qt.vector4d(p.colourKeys[0][1], p.colourKeys[0][2], p.colourKeys[0][3], 1)
            readonly property vector4d colour1: Qt.vector4d(p.colourKeys[1][1], p.colourKeys[1][2], p.colourKeys[1][3], 1)
            readonly property vector4d colour2: Qt.vector4d(p.colourKeys[2][1], p.colourKeys[2][2], p.colourKeys[2][3], 1)
            readonly property vector4d colour3: Qt.vector4d(p.colourKeys[3][1], p.colourKeys[3][2], p.colourKeys[3][3], 1)
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
                resolution: Qt.size(4 * emitter.p.slots - 1, 1)
            }
            vertexShader: Qt.resolvedUrl("shaders/particle.vert.qsb")
            fragmentShader: Qt.resolvedUrl("shaders/particle.frag.qsb")

            Image {
                id: texture
                visible: false
                source: root.url(emitter.p.texture)
                smooth: true
            }
        }
    }

    Emitters {
        group: "back"
    }

    Critters {
        group: "back"
    }

    // The clock's gears, turning with the time: behind the great tree's frame (under the mid
    // layer), or inside the dial, behind the hands. Like the hands, only on the screen that shows
    // the clock: off it they'd still be loaded and turned.
    component ClockGears: Repeater {
        required property bool dial
        model: root.showsClock ? root.clock.gears.filter(g => !!g.dial === dial) : []

        Image {
            required property var modelData
            source: root.url(modelData.file)
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
        name: "mid"
    }

    SwaySprites {
        group: "mid"
    }

    // The clock in the great tree's window: two Cogwork pointers for hands, on local time.
    readonly property var clock: world?.clock ?? null
    readonly property var now: new Date(wholeSecond * 1000)
    readonly property real minuteAngle: (now.getMinutes() + now.getSeconds() / 60) * 6
    readonly property real hourAngle: (now.getHours() % 12 + now.getMinutes() / 60) * 30

    component ClockHands: Repeater {
        model: root.showsClock ? root.clock.hands : []

        Item {
            required property var modelData
            // At the dial's centre; the needle image points left, a quarter turn points it at 12.
            x: root.toX(root.clock.x * root.unitMm)
            y: root.toY(root.clock.y * root.unitMm)
            rotation: 90 + (modelData.name === "hour" ? root.hourAngle : root.minuteAngle)

            Image {
                source: root.url(parent.modelData.file)
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
    // in the next 40 seconds, loaded in the background; screens in one process share them. While
    // it holds its last frame to start again, those from the moment it starts from.
    readonly property var hornetAhead: isNaN(resumeFrom) ? hornet : Life.hornetAt(world, clips, resumeFrom)
    readonly property bool hornetNear: hornetAhead !== null
        && hornetAhead.x * unitMm > me.x - 150 && hornetAhead.x * unitMm < me.x + me.w + 150
    readonly property int lookahead: Math.floor((isNaN(resumeFrom) ? time : resumeFrom) / 5)
    // Until it has faded in, a live screen only loads the sheets of the few seconds from when it
    // was made (or concealed again), so that it shows sooner: those seconds cover its wait and the
    // fade. Then those of the coming 45 seconds.
    property real firstAt: Date.now() / 1000 + timeOffset
    property bool lookaheadOn: false
    readonly property bool firstWave: live && !lookaheadOn
    Timer {
        interval: 350 // the fade, and a little more
        running: root.revealed && !root.lookaheadOn
        onTriggered: root.lookaheadOn = true
    }
    readonly property var clipsAhead: (firstWave
        ? (clips ? Life.critterClips(clips, crittersHere) : [])
            .concat(hornetNear ? Life.clipsAhead(world, clips, firstAt, 4.5) : [])
            .concat(showsBeast ? Life.beastClipsAhead(world, clips, firstAt, 4.5) : [])
        : (hornetNear ? Life.clipsAhead(world, clips, lookahead * 5, 45) : [])
            .concat(showsBeast ? Life.beastClipsAhead(world, clips, lookahead * 5, 45) : [])
            .concat(clips ? Life.critterClips(clips, crittersHere) : []))
        .filter((n, i, all) => all.indexOf(n) === i)
    readonly property real sheetScale: Math.min(1, pxPerUnit / 64)
    property var sheets: ({})
    property var luts: ({})

    // The sheets' Images, by clip: only those of the clips that come and go are made or let go (a
    // new list for a model would make them all again, each leaving then rejoining root.sheets).
    // A clip that leaves the look-ahead keeps its sheet 10 seconds of the scene's clock longer
    // (leftAt, -1 while it's ahead), so that Hornet stepping back and forth across the edge of
    // hornetNear doesn't have a whole screen's sheets decoded again each time. Those are let go at
    // the look-ahead's next 5-second steps: clipsAhead itself may not change for a while.
    ListModel {
        id: sheetList
    }
    property int leaving: 0 // how many of those it keeps
    function syncSheets() {
        const want = clipsAhead;
        const have = {};
        let kept = 0;
        for (let i = sheetList.count - 1; i >= 0; i--) {
            const row = sheetList.get(i);
            if (want.indexOf(row.name) >= 0) {
                have[row.name] = true;
                if (row.leftAt !== -1) {
                    sheetList.setProperty(i, "leftAt", -1);
                }
            } else if (row.leftAt === -1) {
                sheetList.setProperty(i, "leftAt", time);
                kept++;
            } else if (Math.abs(time - row.leftAt) <= 10) { // either way: the clock may have been set back
                kept++;
            } else {
                sheetList.remove(i);
            }
        }
        for (let i = 0; i < want.length; i++) {
            if (!have[want[i]]) {
                sheetList.append({ name: want[i], leftAt: -1 });
            }
        }
        leaving = kept;
    }
    onClipsAheadChanged: syncSheets()
    onLookaheadChanged: if (leaving > 0) Qt.callLater(syncSheets) // once clipsAhead has caught up with it
    Component.onCompleted: {
        syncSheets();
        Reveal.join(root);
        Life.join();
    }

    Item {
        visible: false

        Repeater {
            model: sheetList

            Asset {
                required property string name
                // None if Sprites.qml is made again without it while it's kept.
                readonly property var sheet: root.clips?.[name]

                // From the set made at this screen's density (sheetSet()) as it is, else scaled as
                // it's read.
                req: {
                    const set = root.sheetSet();
                    if (!sheet) {
                        return { url: "", width: 0 };
                    }
                    if (set) {
                        return { url: root.big(set + "/" + sheet.file.slice(sheet.file.lastIndexOf("/") + 1), png), width: 0 };
                    }
                    return { url: root.big(sheet.file, png), width: Math.ceil(sheet.columns * sheet.cellWidth * root.sheetScale) };
                }
                smooth: true
                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.sheets = Object.assign({}, root.sheets, { [name]: this });
                    }
                }
                Component.onDestruction: {
                    if (root.sheets[name] === this) {
                        const left = Object.assign({}, root.sheets);
                        delete left[name];
                        root.sheets = left;
                    }
                }
            }
        }
        Repeater {
            model: root.world?.zones ?? []

            Image {
                required property var modelData

                source: root.url(modelData.grade.lut)
                onStatusChanged: {
                    if (status === Image.Ready) {
                        root.luts = Object.assign({}, root.luts, { [modelData.id]: this });
                    }
                }
                // Let go with its zone (a new world may lack it), unless the zone's new one is in.
                Component.onDestruction: {
                    if (root.luts[modelData.id] === this) {
                        const left = Object.assign({}, root.luts);
                        delete left[modelData.id];
                        root.luts = left;
                    }
                }
            }
        }
    }

    // The small life (tools/world.py CRITTERS, life.js crittersAt): moss flies behind the rock,
    // dragonflies and lilypad flies in Hornet's plane, coloured by the zone they live in (unlit, as
    // the game draws them, in their own tint).
    readonly property var crittersHere: (world?.critters ?? []).filter(c => (c.perches.length ? c.perches.map(p => p[0]) : [c.home[0]])
        .some(x => (x + 6) * unitMm > me.x && (x - 6) * unitMm < me.x + me.w))
    readonly property var critterPoses: crittersHere.length && clips ? Life.critterPosesAt(world, clips, time, crittersHere) : none
    component Critters: Repeater {
        id: critters
        required property string group
        model: root.crittersHere.filter(c => c.layer === critters.group)

        HornetSprite {
            required property var modelData
            required property int index
            // Its place in crittersHere, where its pose is, found by id: modelData is a copy.
            readonly property int slot: root.crittersHere.findIndex(c => c.id === modelData.id)
            readonly property var pose: root.critterPoses[slot] ?? null
            readonly property var zone: root.world.zones.find(z => z.id === modelData.zone) ?? null
            readonly property string clip: pose?.clip ?? ""

            visible: pose !== null && root.sheets[clip] !== undefined && zone !== null && root.luts[zone.id] !== undefined
            sheet: root.clips && root.clips[clip] ? root.clips[clip]
                : { sequence: [0], frames: 1, columns: 1, cellWidth: 1, cellHeight: 1, anchorX: 0, anchorY: 0, pixelsPerUnit: 64 }
            texture: root.sheets[clip] ?? null
            grade: ({ ambient: [0.5, 0.5, 0.5], heroSaturation: 1, saturation: zone ? zone.grade.saturation : 1 })
            lut: zone ? root.luts[zone.id] ?? null : null
            tint: modelData.tint ? Qt.rgba(modelData.tint[0], modelData.tint[1], modelData.tint[2], 1) : "white"
            frame: pose?.frame ?? 0
            mirrored: pose?.facingRight ?? false
            pixelScale: root.pxPerUnit / sheet.pixelsPerUnit * modelData.scale
            x: pose ? root.toX(pose.x * root.unitMm) : 0
            y: pose ? root.toY(pose.y * root.unitMm) : 0
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

    Critters {
        group: "mid"
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
        grade2: root.hornetZone2?.grade ?? null
        lut2: root.hornetZone2 ? root.luts[root.hornetZone2.id] ?? null : null
        blend: root.hornetBlend
        frame: sheet.frames - 1
        mirrored: true // drawn pointing left
        pixelScale: root.pxPerUnit / sheet.pixelsPerUnit
        x: nd ? Math.round(root.toX(nd.x * root.unitMm)) : 0
        y: nd ? Math.round(root.toY(nd.y * root.unitMm)) : 0
        transformOrigin: Item.TopLeft
        rotation: nd ? -nd.angle : 0
    }

    HornetSprite {
        readonly property string clip: root.shownHornet?.clip ?? ""
        readonly property real tilt: root.shownHornet?.angle ?? 0

        visible: root.hornetHere && root.hornetZone !== null && root.sheets[clip] !== undefined
            && root.luts[root.hornetZone.id] !== undefined
        sheet: root.clips && root.clips[clip] ? root.clips[clip]
            : { sequence: [0], frames: 1, columns: 1, cellWidth: 1, cellHeight: 1, anchorX: 0, anchorY: 0, pixelsPerUnit: 64 }
        texture: root.sheets[clip] ?? null
        grade: root.hornetZone?.grade ?? { ambient: [0.5, 0.5, 0.5], heroSaturation: 1, saturation: 1 }
        lut: root.hornetZone ? root.luts[root.hornetZone.id] ?? null : null
        grade2: root.hornetZone2?.grade ?? null
        lut2: root.hornetZone2 ? root.luts[root.hornetZone2.id] ?? null : null
        blend: root.hornetBlend
        frame: root.shownHornet?.frame ?? 0
        mirrored: root.shownHornet?.facingRight ?? false
        pixelScale: root.pxPerUnit / sheet.pixelsPerUnit * (root.shownHornet?.scale ?? 1)
        x: Math.round(root.toX((root.shownHornet?.x ?? 0) * root.unitMm))
        y: Math.round(root.toY((root.shownHornet?.y ?? 0) * root.unitMm))
        transformOrigin: Item.TopLeft
        // Along her Clawline dash she leans into it: nose up, whichever way she faces.
        rotation: mirrored ? -tilt : tilt
    }

    // The station's floor bells, drawn apart from the layer in front of them: they jingle (their
    // shake frames, as the game's BasicSpriteAnimator plays them) while Hornet moves among them,
    // not while she stands still, and around the Bell Beast while it sings, shakes, gets up or
    // lies down; once stirred they finish their shake (its QueueStop) before they fall still.
    readonly property var stirring: beastPose && /Sing|Shake|Wake/.test(beastPose.clip) ? beast.x : null
    property real hornetMovedAt: -1e9
    property var hornetWas: null
    readonly property var animatedHere: world?.animated?.filter(a => (a.x + a.w) * unitMm > me.x && a.x * unitMm < me.x + me.w) ?? none
    onHornetChanged: {
        if (!animatedHere.length) {
            return; // only the floor bells ask whether she moves
        }
        if (hornet && hornetWas && time > wokeAt && Math.hypot(hornet.x - hornetWas[0], hornet.y - hornetWas[1]) > 0.005) {
            hornetMovedAt = time;
        }
        hornetWas = hornet ? [hornet.x, hornet.y] : null;
    }
    readonly property bool hornetMoving: time - hornetMovedAt < 0.15
    Repeater {
        model: root.animatedHere

        Item {
            id: piece
            required property var modelData
            readonly property var a: modelData
            readonly property bool stirred: (root.hornetHere && root.hornetMoving && root.hornet.x > a.x && root.hornet.x < a.x + a.w
                    && root.heroFeetY > a.y - 1.0 && root.heroFeetY < a.y + a.h + 0.4)
                || (root.stirring !== null && Math.abs(a.x + a.w / 2 - root.stirring) < 4.5)
            readonly property real cycle: a.frames / a.fps
            property real startedAt: -1e9
            property real endsAt: -1e9 // the end of the shake it's in: whole cycles from its start
            readonly property bool jingling: root.time < endsAt
            readonly property int frame: jingling ? 1 + Math.floor((root.time - startedAt) * a.fps) % a.frames : 0
            // The screen's clock ticks on its frames while it jingles, and stirs it once each tick has
            // gone through: as the time moves, what stirs it (the Bell Beast's pose, her moves) may
            // not have caught up yet. In a render (live off), as the time is set.
            Component.onCompleted: root.bellItems = root.bellItems.concat([piece])
            Component.onDestruction: root.bellItems = root.bellItems.filter(b => b !== piece)
            function stir() {
                if (!stirred) {
                    return;
                }
                if (root.time >= endsAt) {
                    startedAt = root.time;
                }
                endsAt = startedAt + Math.ceil((root.time - startedAt + 1e-3) / cycle) * cycle;
            }

            Connections {
                target: root
                enabled: !root.live
                function onTimeChanged() {
                    piece.stir();
                }
            }
            readonly property real scale: root.pxPerUnit / root.world.pixelsPerUnit

            x: root.toX(a.x * root.unitMm)
            y: root.toY((a.y + a.h) * root.unitMm)
            width: a.w * root.pxPerUnit
            height: a.h * root.pxPerUnit
            clip: true

            Asset {
                source: root.big(piece.a.sheet, png)
                x: -(piece.a.cell[0] + piece.frame * piece.a.step) * piece.scale
                y: -piece.a.cell[1] * piece.scale
                width: sourceSize.width * piece.scale
                height: sourceSize.height * piece.scale
                smooth: true
            }
        }
    }

    Layer {
        name: "front"
    }

    SwaySprites {
        group: "front"
    }

    // The water, moving (shaders/waterfall.frag, lake.frag): in front of Hornet, under the
    // time of day. Its own clock, wrapped every hour (the shaders work in single precision),
    // only running on the screen that shows it, the only one to load its mask.
    readonly property var water: world?.water ?? null
    readonly property bool showsWater: water !== null
        && (water.lake.left - 1) * unitMm < me.x + me.w && (water.lake.left + water.lake.width + 1) * unitMm > me.x
    component WaterEffect: ShaderEffect {
        required property var area // left, bottom, width, height in units
        readonly property real time: root.showsWater ? root.ambientTime : 0
        readonly property vector2d extent: Qt.vector2d(area.width, area.height)
        readonly property color shallow: root.water ? Qt.rgba(root.water.shallow[0], root.water.shallow[1], root.water.shallow[2], 1) : "black"
        readonly property color light: root.water ? Qt.rgba(root.water.light[0], root.water.light[1], root.water.light[2], 1) : "black"

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
        source: root.showsWater ? root.url(root.water.lake.mask) : ""
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

    Emitters {
        group: "front"
    }

    Air {
        group: "front"
    }

    // Time of day: a veil over everything, then the light sources shining through it.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(root.daylight.color[0], root.daylight.color[1], root.daylight.color[2], 1)
        opacity: root.daylight.opacity
    }

    Layer {
        name: "lights"
        active: root.daylight.lights > 0.01 // loaded only after dusk
        opacity: root.daylight.lights
    }

    // After dark the hands keep a little of their shine, so the time stays readable.
    Item {
        anchors.fill: parent
        opacity: root.daylight.lights * 0.45
        visible: opacity > 0.01

        ClockHands {}
    }

    // The black the screen waits under until revealed. It fades out rather than the scene fading
    // in, which would show the scene's translucent layers through one another, and is back at once
    // when concealed again. Not in renders (live off). Not an OpacityAnimator, on the render
    // thread: once one has run, every timer of the process fires late (Qt 6.11), the water then
    // moving 13 times a second rather than 30.
    Rectangle {
        id: black
        anchors.fill: parent
        color: "black"
        opacity: root.live ? 1 : 0
        visible: opacity > 0

        NumberAnimation {
            id: fade
            target: black
            property: "opacity"
            to: 0
            duration: 300
            easing.type: Easing.InOutQuad
        }
        Connections {
            target: root
            enabled: root.live

            function onRevealedChanged() {
                if (root.revealed) {
                    fade.start();
                } else {
                    fade.stop();
                    black.opacity = 1;
                }
            }
        }
    }

    // Made only when asked for: hidden, it would still be kept up to date, its glyphs made ready
    // to draw.
    Loader {
        active: root.debug

        sourceComponent: Text {
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
}
