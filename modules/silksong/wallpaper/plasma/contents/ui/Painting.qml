/*
 * The world painted in watercolor (tools/world.py build_painting), on screen in the first frame
 * while the world is made behind it (main.qml): locking shows the world being painted on dark
 * paper rather than black. The brush moves on the render thread (UniformAnimator), so it keeps
 * painting at its even pace while the GUI thread makes the world; once the world is drawn under it
 * and the brush has been everywhere, the world washes in through it at that same pace, light
 * first. Painted from the day's colours, it's veiled by the hour's light as the world is. Plain
 * QtQuick, like WorldScene.
 */
import QtQuick
import QtQuick.Window

import "world.js" as World
import "daylight.js" as Daylight
import "painting.js" as Paintings

Item {
    id: root
    visible: present // nothing at all where there's no painting (a world made before)

    required property var screens
    required property string screenName
    required property url dataDir
    property real gapMm: 15
    // As WorldScene's: where the sun is, or the set hours.
    property real latitude: 48.85
    property real longitude: 2.35
    property var dayHours: ["09:30", "10:00", "17:00", "17:30"]
    // The world behind it has everything it shows (WorldScene's revealed).
    property bool revealed: false
    // No paper, bare: where the brush hasn't been, the ground shows (an image of the screen as it
    // was, on Hyprland's lock screen: ../../../quickshell/LockSurface.qml), the world only where it
    // has been.
    property Item ground: null
    readonly property bool bare: ground !== null

    // The brush's pace, all over the screens at once, in how much of the painting shows (world.py
    // times it so): `speed` of it a second, even from the first frame to the end, which comes a
    // little after the world has everything it shows (README, Runtime: about a second). Eased
    // (a slow start, a slowing down while the world was made), it didn't feel even, and the world
    // came while the brush was halfway.
    readonly property real speed: 0.8
    // Then how long the world takes to wash in over it, once the brush has been everywhere: the
    // painting's whole time at that same pace, in the order it was painted.
    readonly property real washFor: 1 / speed

    readonly property var painting: sketch.item?.painting ?? null
    readonly property var me: World.layout(screens, gapMm).screens[screenName] ?? null
    // Its screen's size in pixels: the item itself is first laid out at the lock screen's own size
    // (800 by 600), then at its screen's, and would read all its images for each.
    readonly property var screen: Array.from(screens).find(s => s.name === screenName) ?? null
    readonly property int pxWidth: screen ? screen.width : width
    readonly property int pxHeight: screen ? screen.height : height
    // Whether there's a painting to show (one made by this world.py, for a screen of the layout).
    readonly property bool present: painting !== null && me !== null
    // Its first frame is on screen.
    property bool shown: false
    // Every screen of the process shows its painting (painting.js), or it has waited long enough.
    property bool allShown: false
    // Then the worlds may be made (main.qml), a moment later (below).
    property bool up: false
    // Washed away: the world alone shows.
    property bool gone: false

    // Read as it's made, from a new URL each time (on the desktop it may be made again, for a new
    // world).
    Loader {
        id: sketch
        source: root.dataDir + "/world/Painting.qml?t=" + Date.now()
    }
    // Whether Qt reads QOI (WorldScene's qoiProbe), for the tiles' twins.
    Image {
        id: qoiProbe
        visible: false
        source: "probe.qoi"
    }

    Component.onCompleted: Paintings.join(root)
    Component.onDestruction: Paintings.leave(root)

    // Black where no piece is, until the world washes in (bare: what's under it).
    Rectangle {
        anchors.fill: parent
        color: "black"
        visible: !root.leaving && !root.bare
    }

    // What it paints here, each image read at once, at the size it's drawn (they have to be in the
    // first frame): this screen's own pair (its colours, its timing; tools/derive.py), where one was
    // made for this very screen, its place in the layout and its size; else the world's tiles it
    // shows (World.tilePlace, as the layers' tiles), each decoded at the size it's drawn and cut to
    // what's on screen.
    readonly property var pieces: {
        if (!present || pxWidth <= 0 || pxHeight <= 0) {
            return [];
        }
        const view = (painting.views ?? []).find(v => Math.abs(v.x - me.x) < 1e-6 && Math.abs(v.w - me.w) < 1e-6
            && v.px[0] === pxWidth && v.px[1] === pxHeight);
        if (view) {
            return [{ paint: view.paint, time: view.time, x: 0, y: 0, width: pxWidth, height: pxHeight, decode: 0, clip: null }];
        }
        return painting.paint.map((tile, i) => ({ paint: tile, time: painting.time[i],
                                                  place: World.tilePlace(painting, tile, null, me, pxWidth, pxHeight) }))
            .filter(p => p.place !== null)
            .map(p => ({ paint: p.paint, time: p.time, x: p.place.x, y: p.place.y, width: p.place.width,
                         height: p.place.height, decode: p.place.fw, clip: p.place.clip }));
    }
    // One of a piece's images: the width and the part to keep first, then the file, decoded once,
    // at its size.
    component Part: Image {
        required property var place // its piece: decode, clip
        required property var image // { file, qoi }
        visible: false
        cache: false
        smooth: true
        Component.onCompleted: {
            const qoi = image.qoi && qoiProbe.status === Image.Ready;
            if (place.decode) {
                sourceSize.width = place.decode;
            }
            if (place.clip) {
                sourceClipRect = Qt.rect(place.clip[0], place.clip[1], place.clip[2], place.clip[3]);
            }
            source = root.dataDir + "/world/" + (qoi ? image.file.slice(0, -4) + ".qoi" : image.file) + "?v=" + root.painting.build;
        }
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

            Part {
                id: colours
                place: piece.modelData
                image: piece.modelData.paint
            }
            Part {
                id: times
                place: piece.modelData
                image: piece.modelData.time
            }
            ShaderEffect {
                id: brush
                anchors.fill: parent
                property variant paint: colours
                property variant timing: times
                // (bare or not, the sampler needs a texture: the paint's when there's no ground)
                property variant ground: root.ground ?? colours
                property vector4d groundRect: Qt.vector4d(piece.x / root.width, piece.y / root.height,
                                                          piece.width / root.width, piece.height / root.height)
                property real clock: 0
                property real speed: root.speed
                property real end: 0
                property real endFor: root.endFor
                property real washFor: root.washFor
                property color veil: root.veil
                property color light: root.light
                property real bare: root.bare ? 1 : 0
                fragmentShader: Qt.resolvedUrl("shaders/watercolor.frag.qsb")
            }
            // The brush's clock, in seconds: started as it's made, it runs from the first frame,
            // on the render thread.
            UniformAnimator {
                target: brush
                uniform: "clock"
                from: 0
                to: 600
                duration: 600000
                running: true
            }
            // The end's (leaving, below), on the render thread too; then the world alone shows.
            UniformAnimator {
                target: brush
                uniform: "end"
                from: 0
                to: 1
                duration: root.endFor * 1000
                running: root.leaving
                onFinished: root.gone = true
            }
        }
    }

    // The hour's light, as WorldScene's veil over its world, at the moment it's made: its colour,
    // and how much of it (alpha), laid over the painting in the shader so that it washes away with
    // it.
    readonly property var daylight: Daylight.lightingAt(new Date(), latitude, longitude, dayHours)
    readonly property color veil: Qt.rgba(daylight.color[0], daylight.color[1], daylight.color[2], daylight.opacity)
    // And its light shafts, which the painting has apart (world.py): their colour, as strong as
    // WorldScene's sun has them.
    readonly property var lightColour: painting?.light ?? [1, 1, 1]
    readonly property color light: Qt.rgba(lightColour[0], lightColour[1], lightColour[2], Math.max(0.12, 1 - daylight.lights))

    // On screen: the worlds may be made once every screen's painting is (painting.js), and the
    // brush's time counts from now. Its time is told by the clock at each frame, not by Timers:
    // those run on the GUI thread's animation clock, which stands still while only the render
    // thread animates (a second's Timer then takes 1.6).
    property real shownAt: 0
    Connections {
        target: root.Window.window
        enabled: root.present && !root.leaving

        function onFrameSwapped() {
            if (!root.shown) {
                root.shown = true;
                root.shownAt = Date.now();
                Paintings.shown();
            }
            if (!root.allShown && Date.now() - root.shownAt >= 400) {
                root.allShown = true; // a screen whose painting never showed (switched off) holds no one back
            }
            if (!root.covered && Date.now() - root.shownAt >= root.coverAt * 1000) {
                root.covered = true;
            }
            if (root.uncover && ++root.framesUncovered >= 2 && !root.framed) {
                root.framed = true;
                Paintings.framed();
            }
        }
    }
    // A screen whose painting never shows at all doesn't hold its world back for long either.
    Timer {
        interval: 1500
        running: root.present && !root.shown
        onTriggered: root.allShown = true
    }
    // The world is made a moment after: not from within the frame that shows the last painting.
    // Each of the lock screen's windows takes the compositor's word on its surface (configure) on
    // the GUI thread, and until it has, its render thread may draw nothing on its own (Qt Wayland's
    // allowsIndependentThreadedRendering); the screens' surfaces being set up anew as the last one
    // shows, a world made at once would stop every brush for as long as it takes (0.65 s).
    Timer {
        interval: 30
        running: root.allShown && !root.up
        onTriggered: root.up = true
    }

    // The world behind may show (main.qml) once it has everything it shows and the brush has been
    // everywhere, under the painting: its images go to the GPU at its first frame, which holds the
    // brush back a moment. Once that frame is drawn (the next but one) on every screen
    // (painting.js), the end: the worlds wash in through the paintings together at the brush's
    // pace, light first as the washes were painted: each place goes from painting to world in a few
    // frames along a ragged front, rather than both showing everywhere as a fade would.
    readonly property bool uncover: revealed && covered
    // Not before the brush has been everywhere: 93% of its time, which with the brush a tenth
    // quicker than its time (watercolor.frag's behind) is all of it, so that the world never comes
    // through where it hasn't painted (bare: the screen as it was) nor while it's still going.
    // Should no frame tell it, a while after the world is in.
    property bool covered: false
    readonly property real coverAt: 0.93 / speed
    Timer {
        interval: 2000
        running: root.revealed && !root.covered
        onTriggered: root.covered = true
    }
    property int framesUncovered: 0
    property bool framed: false
    property bool leaving: false
    // The end's timing, in seconds (watercolor.frag): the brush's last, should it not be done yet
    // (set as it starts, leave()), and the world washing in meanwhile, from the start.
    property real finishFor: 0
    readonly property real endFor: Math.max(finishFor, washFor)
    // How long the brush would take to come to the end from now.
    function finishNow() {
        return Math.max(0, 1 - speed * (Date.now() - shownAt) / 1000) / speed;
    }
    // The end, the brush taking finish seconds to come to it.
    function leave(finish) {
        if (!leaving) {
            finishFor = finish;
            leaving = true;
        }
    }
    Timer {
        interval: 500 // should no frame come, or another screen's not
        running: root.uncover && !root.leaving
        onTriggered: {
            root.leave(root.finishNow());
            Paintings.framed();
        }
    }
    // Should no piece be there to wash in (none on this screen), gone at once; should the end
    // never be told, gone a while after.
    onLeavingChanged: if (leaving && pieces.length === 0) gone = true
    Timer {
        interval: root.endFor * 1000 + 1000
        running: root.leaving
        onTriggered: root.gone = true
    }
}
