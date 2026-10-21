/*
 * The world drawn in lines (tools/world.py build_drawing), on screen in the first frame while the
 * world is made behind it (main.qml): locking shows the world being drawn rather than black. The
 * pen moves on the render thread (UniformAnimator), so it keeps drawing while the GUI thread makes
 * the world; once the world has everything it shows (revealed) and the pen has finished, the
 * drawing fades away over it, as the black did. Plain QtQuick, like WorldScene.
 */
import QtQuick
import QtQuick.Window

import "world.js" as World
import "drawing.js" as Drawings

Item {
    id: root
    visible: present // nothing at all where there's no drawing (a world made before)

    required property var screens
    required property string screenName
    required property url dataDir
    property real gapMm: 15
    // The world behind it has everything it shows (WorldScene's revealed).
    property bool revealed: false

    // How long the pen takes, all over the screens at once: about what the world then takes to
    // have everything it shows (README, Runtime). It always finishes.
    readonly property int duration: 1000

    readonly property var drawing: sketch.item?.drawing ?? null
    readonly property var me: World.layout(screens, gapMm).screens[screenName] ?? null
    // Whether there's a drawing to show (one made by this world.py, for a screen of the layout).
    readonly property bool present: drawing !== null && me !== null
    // Its first frame is on screen.
    property bool drawn: false
    // Every screen of the process shows its drawing (drawing.js), or it has waited long enough:
    // the worlds may be made.
    property bool up: false
    // The pen has finished.
    property bool done: false
    // Faded away: the world alone shows.
    property bool gone: false

    // Read as it's made, from a new URL each time (on the desktop it may be made again, for a new
    // world).
    Loader {
        id: sketch
        source: root.dataDir + "/world/Drawing.qml?t=" + Date.now()
    }
    // Whether Qt reads QOI (WorldScene's qoiProbe), for the tiles' twins.
    Image {
        id: qoiProbe
        visible: false
        source: "probe.qoi"
    }

    Component.onCompleted: Drawings.join(root)
    Component.onDestruction: Drawings.leave(root)

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    // What it draws here, each piece read at once, at the size it's drawn (they have to be in the
    // first frame): this screen's own image of it (tools/derive.py), one read, where one was made for
    // this very screen, its place in the layout and its size; else the world's tiles it shows
    // (World.tilePlace, as the layers' tiles), each decoded at the size it's drawn and cut to what's
    // on screen.
    readonly property var pieces: {
        if (!present || width <= 0 || height <= 0) {
            return [];
        }
        const view = (drawing.views ?? []).find(v => Math.abs(v.x - me.x) < 1e-6 && Math.abs(v.w - me.w) < 1e-6
            && v.px[0] === width && v.px[1] === height);
        if (view) {
            return [{ file: view.file, qoi: view.qoi, x: 0, y: 0, width: width, height: height, decode: 0, clip: null }];
        }
        return drawing.tiles.map(tile => ({ tile: tile, place: World.tilePlace(drawing, tile, null, me, width, height) }))
            .filter(p => p.place !== null)
            .map(p => ({ file: p.tile.file, qoi: p.tile.qoi, x: p.place.x, y: p.place.y, width: p.place.width,
                         height: p.place.height, decode: p.place.fw, clip: p.place.clip }));
    }
    Repeater {
        model: root.pieces

        Item {
            id: piece
            required property var modelData

            x: modelData.x
            y: modelData.y
            width: modelData.width
            height: modelData.height

            Image {
                id: lines
                visible: false
                cache: false
                smooth: true
                // The width and the part to keep first, then the file: decoded once, at its size.
                Component.onCompleted: {
                    const p = piece.modelData;
                    const qoi = p.qoi && qoiProbe.status === Image.Ready;
                    if (p.decode) {
                        sourceSize.width = p.decode;
                    }
                    if (p.clip) {
                        sourceClipRect = Qt.rect(p.clip[0], p.clip[1], p.clip[2], p.clip[3]);
                    }
                    source = root.dataDir + "/world/" + (qoi ? p.file.slice(0, -4) + ".qoi" : p.file) + "?v=" + root.drawing.build;
                }
            }
            ShaderEffect {
                id: pen
                anchors.fill: parent
                property variant source: lines
                property real progress: 0
                fragmentShader: Qt.resolvedUrl("shaders/drawing.frag.qsb")
            }
            // Started as it's made, it runs from the first frame, on the render thread. Its end,
            // told back to the GUI thread, is when the pen has finished (a screen whose world is
            // still hidden draws no frame after the pen's last).
            UniformAnimator {
                target: pen
                uniform: "progress"
                from: 0
                to: 1
                duration: root.duration
                running: true
                onFinished: root.done = true
            }
        }
    }

    // On screen: the worlds may be made once every screen's drawing is (drawing.js), and the
    // pen's time counts from now. Its time is told by the clock at each frame (the pen's, then the
    // world's), not by Timers: those run on the GUI thread's animation clock, which stands still
    // while the pen moves on the render thread (a second's Timer then takes 1.6).
    property real drawnAt: 0
    function tell() {
        const since = Date.now() - drawnAt;
        if (!up && since >= 400) {
            up = true; // a screen whose drawing never showed (switched off) holds no one back
        }
        if (since >= duration - 20) { // (from the pen's last frame)
            done = true;
        }
    }
    Connections {
        target: root.Window.window
        enabled: root.present && !root.leaving

        function onFrameSwapped() {
            if (!root.drawn) {
                root.drawn = true;
                root.drawnAt = Date.now();
                Drawings.shown();
            }
            root.tell();
            if (root.uncover && ++root.framesUncovered >= 2 && !root.framed) {
                root.framed = true;
                Drawings.framed();
            }
        }
    }
    onRevealedChanged: if (drawn) tell()
    // A screen whose drawing never shows at all doesn't hold its world back for long either.
    Timer {
        interval: 1500
        running: root.present && !root.drawn
        onTriggered: root.up = true
    }

    // The world behind may show (main.qml): it has everything it shows and the pen has finished.
    // Hidden until then, it doesn't hold the pen back as its images go to the GPU at its first
    // frame; they go now, under the finished drawing. Once that frame is drawn (the next but one)
    // on every screen (drawing.js), the drawings fade away over the worlds together.
    readonly property bool uncover: revealed && done
    property int framesUncovered: 0
    property bool framed: false
    property bool leaving: false
    Timer {
        interval: 500 // should no frame come, or another screen's not
        running: root.uncover && !root.leaving
        onTriggered: root.leaving = true
    }
    NumberAnimation {
        id: fade
        target: root
        property: "opacity"
        to: 0
        duration: 300
        easing.type: Easing.InOutQuad
        onFinished: root.gone = true
    }
    onLeavingChanged: if (leaving) fade.start()
}
