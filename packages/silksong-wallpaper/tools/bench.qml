/*
 * Measures the world as the lock screen runs it: one window per screen in one process, live,
 * at a chosen time of day. Run by tools/bench.py (which also samples CPU and GPU use), on a
 * headless compositor so nothing shows on the desk:
 *
 *   qml tools/bench.qml -- --t0 EPOCH_MS [--offset SECONDS] [--seconds N] [--only SCREEN]
 *       [--motion N] [--greeter] [--fader] [--busy-anim] [--hide-at S] [--show-at S]
 *       [--pause-at S] [--resume-at S] [--jump-at S --jump SECONDS] [--trace-ticks SCREEN]
 *       [--trace-frames SCREEN[,SCREEN...]]
 *
 * Logs to stderr: "WINDOW screen window" as each window is made, "LOAD screen ms ready/total"
 * each time a screen's images change state, "FIRST_FRAME screen ms" when its window first shows,
 * "REVEAL screen ms {pending, missing}" when a scene that waits for its images shows them (how
 * many it still waited for, the sheets it then draws without), "READY screen ms" once
 * all its images are in, then over the measured run "RUN_START ms {at, hornet}" (the scene's
 * clock, the screens Hornet is on), "SECOND ms {frames}" every second, "HIDE", "SHOW", "PAUSE",
 * "RESUME" and "JUMP" with the same fields, "RUN_END ms {frames}" (frames drawn per window since
 * the start) and "TICKS {ticks}" (how many times each scene's time moved). After RESUME, "RESUMED
 * screen ms {held, stale, behind, lacking, missing}" a second after each window first drew the
 * moment it resumed at: how long after RESUME that was, the frames it drew before of the moment it
 * paused at, how far behind the clock its time then was, and over that second the frames drawn
 * without a sheet and the sheets they lacked. --trace-ticks logs "TICK screen ms
 * time" each time one screen's time moves and "FRAME screen ms" each time it draws;
 * --trace-frames follows what each of those screens shows at every tick and logs, after the run,
 * "FRAME_TRACE screen {table}": for each thing on it that changes by frames, how often it changed
 * and whether it skipped, held or drew late any of them (tools/bench_frames.js).
 *
 * As kscreenlocker_greet runs it: each scene is made in its window, at its size, as main.qml
 * makes it. --greeter only makes it after holding the GUI thread for a moment, as the greeter
 * makes each wallpaper before the lock screen it goes in, and the wallpaper waits for its window;
 * --fader draws it through the lock screen's WallpaperFader (tools/bench_fader.qml). --motion
 * sets the scenes' Motion, as the wallpaper's setting (0, every frame, otherwise). --busy-anim keeps an animation
 * running throughout, as a panel or an applet animating does in plasmashell: every timer of the
 * process then rides the animation clock. --hide-at and --show-at (seconds into the run) hide and
 * show every scene, as Plasma does on an activity switch; --pause-at and --resume-at pause and
 * resume them, as the desktop does while a window is focused (main.qml PauseWhen); --jump-at moves
 * the wall clock by --jump seconds.
 */
import QtQuick
import QtQuick.Window
import QtCore

import "../plasma/contents/ui"
import "../plasma/contents/ui/life.js" as Life
import "bench_frames.js" as Frames
import "desk.js" as Desk

QtObject {
    id: bench

    readonly property var screens: Desk.screens
    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    function arg(name, fallback) {
        const i = args.indexOf(name);
        return i >= 0 ? args[i + 1] : fallback;
    }
    function flag(name) {
        return args.indexOf(name) >= 0;
    }
    readonly property real t0: Number(arg("--t0", Date.now()))
    readonly property real seconds: Number(arg("--seconds", 20))
    readonly property string only: arg("--only", "")
    readonly property bool greeter: flag("--greeter")
    readonly property bool noPainting: flag("--no-painting")
    readonly property bool fader: flag("--fader")
    readonly property real hideAt: Number(arg("--hide-at", -1))
    readonly property real showAt: Number(arg("--show-at", -1))
    readonly property real pauseAt: Number(arg("--pause-at", -1))
    readonly property real resumeAt: Number(arg("--resume-at", -1))
    readonly property real jumpAt: Number(arg("--jump-at", -1))
    readonly property real jump: Number(arg("--jump", 0))
    readonly property string traceTicks: arg("--trace-ticks", "")
    readonly property var traceFrames: arg("--trace-frames", "").split(",")
    readonly property int motion: Number(arg("--motion", 0)) // as the wallpaper's Motion setting
    readonly property bool busyAnim: flag("--busy-anim")
    readonly property url dataDir: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/silksong-wallpaper"

    property real offset: Number(arg("--offset", 0))
    property var ready: ({})
    property bool running: false

    function since() {
        return Math.round(Date.now() - t0);
    }

    // Every Image under an item (the sources of ShaderEffects included).
    function images(item, out) {
        for (const c of item.children ?? []) {
            if (c.status !== undefined && c.sourceSize !== undefined && c.progress !== undefined && String(c.source) !== "") {
                out.push(c);
            }
            images(c, out);
        }
        return out;
    }

    // The floor bells' pieces under an item (those that jingle).
    function bells(item, out) {
        for (const c of item.children ?? []) {
            if (c.jingling !== undefined && c.startedAt !== undefined) {
                out.push(c);
            }
            bells(c, out);
        }
        return out;
    }

    // A per-window counter ("frames", "ticks") as { screen: count }.
    function counts(what) {
        const out = {};
        for (let i = 0; i < windows.count; i++) {
            const w = windows.objectAt(i);
            out[w.modelData.name] = w[what];
        }
        return out;
    }

    function mark(what) {
        console.warn(`${what} ${since()} ${JSON.stringify(counts("frames"))}`);
    }

    // The clips a scene draws whose sheet it doesn't have.
    function missing(s) {
        const drawn = [s.shownHornet?.clip, s.shownHornet?.needle ? "Harpoon Needle" : null, s.beastPose?.clip]
            .concat(s.critterPoses.map(p => p?.clip));
        return drawn.filter((c, i) => c && s.sheets[c] === undefined && drawn.indexOf(c) === i);
    }

    property Instantiator windows: Instantiator {
        model: bench.screens.filter(s => !bench.only || s.name === bench.only)

        Window {
            id: win
            required property var modelData
            readonly property Item scene: wallpaper.item
            property bool seated: !bench.greeter
            property int frames: 0
            property int ticks: 0
            property bool drawn: false
            property var resumed: null // what it draws once resumed, for the RESUMED line
            readonly property bool tracing: bench.traceFrames.indexOf(modelData.name) >= 0
            property var bells: [] // its floor bells' pieces
            property var samples: [] // what it showed at each tick of the run

            width: modelData.width
            height: modelData.height
            visible: true
            color: "black"
            // The greeter makes each wallpaper before it has a window, and parents it to its own
            // screen's window once that screen's lock screen is made: about 90 ms of the GUI
            // thread later (180 for the first screen, in kscreenlocker_greet --testing). Only
            // then is the scene made (main.qml: until it has a window, its Screen is the primary
            // screen).
            Component.onCompleted: {
                console.warn(`WINDOW ${modelData.name} ${win}`);
                if (bench.greeter) {
                    const madeAt = Date.now();
                    while (Date.now() - madeAt < 90) {
                        // The GUI thread is held as the greeter's is, making the lock screen.
                    }
                    seated = true;
                }
            }
            onFrameSwapped: {
                if (!drawn) {
                    drawn = true;
                    console.warn(`FIRST_FRAME ${modelData.name} ${bench.since()}`);
                }
                frames++;
                if (bench.traceTicks === modelData.name) {
                    console.warn(`FRAME ${modelData.name} ${bench.since()}`);
                }
                const r = resumed;
                if (r !== null && scene.time < r.time) {
                    r.stale++;
                } else if (r !== null) {
                    const at = bench.since();
                    if (r.held < 0) {
                        r.held = at - r.at;
                        r.behind = Math.round(Date.now() + bench.offset * 1000 - scene.time * 1000);
                    }
                    const missing = bench.missing(scene);
                    r.lacking += missing.length > 0 ? 1 : 0;
                    r.missing = r.missing.concat(missing.filter(c => r.missing.indexOf(c) < 0));
                    if (at - r.at - r.held >= 1000) {
                        const info = { held: r.held, stale: r.stale, behind: r.behind, lacking: r.lacking, missing: r.missing };
                        console.warn(`RESUMED ${modelData.name} ${r.at + r.held} ${JSON.stringify(info)}`);
                        resumed = null;
                    }
                }
            }

            // Made in its window at its size, as main.qml makes it: once every screen shows its
            // painting, where there's one, a little at a time.
            Loader {
                id: wallpaper
                anchors.fill: parent
                asynchronous: true
                active: win.seated && width > 0 && height > 0 && (!(painting.item?.present ?? false) || painting.item.up)
                visible: !(painting.item?.present ?? false) || painting.item.uncover
                sourceComponent: WorldScene {
                    screens: bench.screens
                    gapMm: Desk.gapMm
                    screenName: win.modelData.name
                    dataDir: bench.dataDir
                    timeOffset: bench.offset
                    coverFirst: !(painting.item?.present ?? false)
                }
                onLoaded: {
                    item.everyFrame = bench.motion === 0;
                    item.nearHz = [60, 60, 30, 0][bench.motion] ?? 60;
                }
            }
            // The world painted meanwhile, over it, as main.qml shows it (--no-painting: not).
            property bool paintingGone: false
            Loader {
                id: painting
                anchors.fill: parent
                active: win.seated && !bench.noPainting && !win.paintingGone
                sourceComponent: Painting {
                    screens: bench.screens
                    gapMm: Desk.gapMm
                    screenName: win.modelData.name
                    dataDir: bench.dataDir
                    revealed: wallpaper.item?.revealed ?? false
                }
            }
            Connections {
                target: painting.item
                function onShownChanged() {
                    console.warn(`PAINTING ${win.modelData.name} ${bench.since()} shown`);
                }
                function onUpChanged() {
                    console.warn(`PAINTING ${win.modelData.name} ${bench.since()} up`);
                }
                function onUncoverChanged() {
                    console.warn(`PAINTING ${win.modelData.name} ${bench.since()} uncover`);
                }
                function onLeavingChanged() {
                    console.warn(`PAINTING ${win.modelData.name} ${bench.since()} wash`);
                }
                function onGoneChanged() {
                    console.warn(`PAINTING ${win.modelData.name} ${bench.since()} gone`);
                    win.paintingGone = true;
                }
            }

            // The lock screen's fader, made after the wallpaper as in the greeter.
            Loader {
                anchors.fill: parent
                active: bench.fader && wallpaper.item !== null
                source: "bench_fader.qml"
                onLoaded: item.wallpaper = wallpaper
            }

            Connections {
                target: win.scene
                function onTimeChanged() {
                    win.ticks++;
                    if (bench.traceTicks === win.modelData.name) {
                        console.warn(`TICK ${win.modelData.name} ${bench.since()} ${win.scene.time.toFixed(4)}`);
                    }
                    if (win.tracing && bench.running) {
                        // Once the tick has gone through: what's bound to the time is then up to date.
                        const t = win.scene.time;
                        Qt.callLater(() => {
                            if (win.scene.time === t) {
                                win.samples.push(Frames.sample(win.scene, win.bells));
                            }
                        });
                    }
                }
            }
            Connections {
                target: win.scene
                ignoreUnknownSignals: true
                function onRevealedChanged() {
                    if (!win.scene.revealed) {
                        return;
                    }
                    // Once its clock has moved to the moment it shows: whatever it draws then
                    // without its sheet.
                    const at = bench.since();
                    Qt.callLater(() => {
                        const s = win.scene;
                        console.warn(`REVEAL ${win.modelData.name} ${at} ${JSON.stringify({ pending: s.pending, missing: bench.missing(s) })}`);
                    });
                }
            }

            // The load: how many of the screen's images are in, each time that changes. Looked at
            // every 50 ms, as walking the scene takes the GUI thread from what it measures.
            Timer {
                interval: 50
                repeat: true
                running: true
                property string last: ""
                property real changed: 0
                onTriggered: {
                    if (!win.scene) {
                        return;
                    }
                    const all = bench.images(win.scene, []);
                    // One that failed is in too, as the scene counts it: nothing more comes of it
                    // (the QOI probe, without KDE's image formats).
                    const isIn = i => i.status === Image.Ready || i.status === Image.Error;
                    const ready = all.filter(isIn).length;
                    const now = bench.since();
                    const key = `${ready}/${all.length}`;
                    if (key !== last) {
                        last = key;
                        changed = now;
                        console.warn(`LOAD ${win.modelData.name} ${now} ${key}`);
                    }
                    // Settled: everything in, and nothing new asked for in a second.
                    if (win.scene.world && all.length > 0 && ready === all.length && now - changed > 1000) {
                        running = false;
                        console.warn(`READY ${win.modelData.name} ${changed}`);
                        bench.ready = Object.assign({}, bench.ready, { [win.modelData.name]: changed });
                    } else if (now > 30000) {
                        running = false;
                        console.warn(`TIMEOUT ${win.modelData.name} ${now} ${key}`);
                        bench.ready = Object.assign({}, bench.ready, { [win.modelData.name]: -1 });
                    }
                }
            }
        }
    }

    onReadyChanged: {
        if (windows.count > 0 && Object.keys(ready).length === windows.count && !running) {
            running = true;
            const hornet = [];
            for (let i = 0; i < windows.count; i++) {
                const w = windows.objectAt(i);
                w.frames = 0;
                w.ticks = 0;
                w.bells = bench.bells(w.scene, []);
                if (w.scene.hornetHere) {
                    hornet.push(w.modelData.name);
                }
            }
            const at = new Date(windows.objectAt(0).scene.time * 1000).toTimeString().slice(0, 8);
            console.warn(`RUN_START ${since()} ${JSON.stringify({ at, hornet })}`);
            run.start();
            second.start();
            if (hideAt >= 0) {
                hider.start();
            }
            if (showAt >= 0) {
                shower.start();
            }
            if (pauseAt >= 0) {
                pauser.start();
            }
            if (resumeAt >= 0) {
                resumer.start();
            }
            if (jumpAt >= 0) {
                jumper.start();
            }
        }
    }

    property Timer second: Timer {
        interval: 1000
        repeat: true
        onTriggered: bench.mark("SECOND")
    }
    property Timer hider: Timer {
        interval: bench.hideAt * 1000
        onTriggered: {
            bench.mark("HIDE");
            for (let i = 0; i < bench.windows.count; i++) {
                bench.windows.objectAt(i).scene.parent.visible = false;
            }
        }
    }
    property Timer shower: Timer {
        interval: bench.showAt * 1000
        onTriggered: {
            bench.mark("SHOW");
            for (let i = 0; i < bench.windows.count; i++) {
                bench.windows.objectAt(i).scene.parent.visible = true;
            }
        }
    }
    property Timer pauser: Timer {
        interval: bench.pauseAt * 1000
        onTriggered: {
            bench.mark("PAUSE");
            for (let i = 0; i < bench.windows.count; i++) {
                bench.windows.objectAt(i).scene.paused = true;
            }
        }
    }
    property Timer resumer: Timer {
        interval: bench.resumeAt * 1000
        onTriggered: {
            bench.mark("RESUME");
            for (let i = 0; i < bench.windows.count; i++) {
                const w = bench.windows.objectAt(i);
                w.resumed = { at: bench.since(), time: Date.now() / 1000 + bench.offset, held: -1, stale: 0, behind: 0, lacking: 0, missing: [] };
                w.scene.paused = false;
            }
        }
    }
    property Timer jumper: Timer {
        interval: bench.jumpAt * 1000
        onTriggered: {
            bench.mark("JUMP");
            bench.offset += bench.jump;
        }
    }
    // Kept running with --busy-anim, as an animation elsewhere in the process.
    property real spin: 0
    property NumberAnimation spinner: NumberAnimation {
        target: bench
        property: "spin"
        from: 0
        to: 360
        duration: 1000
        loops: Animation.Infinite
        running: bench.busyAnim
    }

    property Timer run: Timer {
        interval: bench.seconds * 1000
        onTriggered: {
            // Qt.quit() only ends the process a moment later, and nothing may be marked after
            // the run: the second due at the same moment would otherwise come after it.
            for (const timer of [bench.second, bench.hider, bench.shower, bench.pauser, bench.resumer, bench.jumper]) {
                timer.stop();
            }
            bench.mark("RUN_END");
            console.warn(`TICKS ${JSON.stringify(bench.counts("ticks"))}`);
            for (let i = 0; i < bench.windows.count; i++) {
                const w = bench.windows.objectAt(i);
                if (w.tracing) {
                    console.warn(`FRAME_TRACE ${w.modelData.name} ${JSON.stringify(Frames.analyse(w.samples, w.scene, Life))}`);
                }
            }
            Qt.quit();
        }
    }
}
