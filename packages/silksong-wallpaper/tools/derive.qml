/*
 * What tools/derive.py has Qt itself draw for this desk (desk.js), offscreen on its software
 * renderer, so that the pixels are the ones Qt would make of the world's images as the wallpaper
 * reads them: for each screen and layer, the texels each tile shows there (World.tilePlace:
 * decoded at the same size, cut the same way), and each of Hornet's sheets (the Bell Beast's, the
 * small life's) at each screen's density, at the size WorldScene asks for it there.
 *
 *   QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software qml tools/derive.qml -- WORLD_QML SPRITES_QML OUT_DIR
 *
 * Writes OUT_DIR/<screen>_<layer>_<n>.png and OUT_DIR/<folder>_<sheet>.png, then logs "DERIVED
 * {views, sheetSets}": each screen's place in the layout and size, with for each layer the texels
 * it shows of each tile (their file; where the whole tile goes, fx and fy; where they are in the
 * scaled tile, tx and ty; how many pixels each covers, sx and sy); and each density's pixels per
 * unit, by the folder its sheets go in. Logs "FAILED why" and exits with 1 if an image can't be
 * read or written.
 */
import QtQuick
import QtQuick.Window

import "desk.js" as Desk
import "../plasma/contents/ui/world.js" as World

Window {
    id: win

    readonly property var args: Qt.application.arguments.slice(Qt.application.arguments.indexOf("--") + 1)
    readonly property string worldDir: "file://" + args[0].slice(0, args[0].lastIndexOf("/"))
    readonly property var world: read(args[0], "world")
    readonly property var clips: read(args[1], "clips") ?? {}
    readonly property string outDir: args[2]

    // What a generated QML file (World.qml, Sprites.qml) holds, or null if it can't be read.
    function read(file, name) {
        const made = Qt.createComponent("file://" + file).createObject(null);
        const value = made?.[name] ?? null;
        made?.destroy();
        return value;
    }

    // What to draw: each screen's share of each layer's tiles, then each sheet at each density
    // under the sheets' own 64 pixels a unit (once for a density two screens share).
    readonly property var plan: {
        const jobs = [], views = [], sheetSets = {};
        if (!world) {
            return { jobs: jobs, derived: null };
        }
        const layout = World.layout(Desk.screens, Desk.gapMm);
        for (const s of Desk.screens) {
            const me = layout.screens[s.name];
            const view = { x: me.x, w: me.w, px: [s.width, s.height], layers: {} };
            // The layers, and the drawing the lock screen shows while it makes the world.
            for (const name of ["back", "mid", "front", "lights", "drawing"]) {
                view.layers[name] = [];
                for (const tile of (name === "drawing" ? world.drawing : world.layers[name]) ?? []) {
                    const place = World.tilePlace(world, tile, null, me, s.width, s.height);
                    if (place) {
                        const file = `${s.name}_${name}_${view.layers[name].length}.png`;
                        view.layers[name].push({ file: file, fx: place.fx, fy: place.fy, tx: place.clip[0], ty: place.clip[1],
                                                 sx: place.sx, sy: place.sy });
                        jobs.push({ source: tile.file, width: place.fw, clip: place.clip, file: file });
                    }
                }
            }
            views.push(view);

            // As WorldScene works out its pixels a unit and the width it asks for each sheet.
            const pxPerUnit = s.width / me.w * world.unitMm;
            const folder = `hornet@${Math.round(pxPerUnit)}`;
            if (pxPerUnit < 64 && !(folder in sheetSets)) {
                sheetSets[folder] = pxPerUnit;
                for (const c of Object.values(clips)) {
                    jobs.push({ source: c.file, width: Math.ceil(c.columns * c.cellWidth * Math.min(1, pxPerUnit / 64)),
                                file: `${folder}_${c.file.slice(c.file.lastIndexOf("/") + 1)}` });
                }
            }
        }
        return { jobs: jobs, derived: { views: views, sheetSets: sheetSets } };
    }
    property int done: 0

    width: 1920
    height: 1200
    visible: true

    // One image at a time, read as WorldScene reads it (its width, then the part kept, given
    // before the file, so that it's read once) and drawn at its own size, texel for texel.
    Image {
        id: image
        asynchronous: false
        cache: false
    }

    function fail(why) {
        console.warn(`FAILED ${why}`);
        Qt.exit(1);
    }
    function next() {
        if (!world) {
            fail(`can't read ${args[0]}`);
            return;
        }
        const job = plan.jobs[done];
        if (!job) {
            console.warn(`DERIVED ${JSON.stringify(plan.derived)}`);
            Qt.quit();
            return;
        }
        image.source = "";
        image.sourceSize.width = job.width;
        image.sourceClipRect = job.clip ? Qt.rect(job.clip[0], job.clip[1], job.clip[2], job.clip[3]) : undefined;
        image.source = `${worldDir}/${job.source}`;
        if (image.status !== Image.Ready) {
            fail(`can't read ${job.source}`);
            return;
        }
        const drawing = image.grabToImage(result => {
            if (!result.saveToFile(`${outDir}/${job.file}`)) {
                fail(`can't write ${job.file}`);
                return;
            }
            done++;
            Qt.callLater(next);
        });
        if (!drawing) {
            fail(`can't draw ${job.source}`);
        }
    }
    // Once the event loop runs, which Qt.exit() needs.
    Component.onCompleted: Qt.callLater(next)
}
