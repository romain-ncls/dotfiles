/*
 * Checks when life.js says Hornet and the Bell Beast next change (hornetChangesAt, beastNext)
 * against what they show, without Plasma:
 *
 *   node tools/check_events.js [LIFE_JS] [DAYS] [YYYY-MM-DD]
 *
 * For DAYS days (3 by default) from 04:00 on the date (today by default), follows each of them as
 * a screen's clock does: it asks again just after the moment it was given, and on every sample
 * while she moves. Sampled every 1/240 s in between, anything that shows differently before that
 * moment (her clip and its cell, where she is, which way she faces, her needle and its silk) is
 * an early change, one a screen would draw late; the Bell Beast never moves, so a moment no later
 * than it was asked would have its screen drawn on every frame. Exits with an error on either.
 * Also prints how many moments a day each needed, against a screen drawing 60 frames a second.
 */
const fs = require("fs");
const path = require("path");
const os = require("os");

const root = path.join(__dirname, "..");
const data = path.join(os.homedir(), ".local/share/silksong-wallpaper");
const file = process.argv[2] || path.join(root, "plasma/contents/ui/life.js");
const src = fs.readFileSync(file, "utf8").replace(".pragma library", "");
const Life = new Function(src + "\nreturn { dayStart, hornetAt, hornetChangesAt, beastAt, beastNext };")();
const grab = (file, prop) => {
    const t = fs.readFileSync(file, "utf8");
    const i = t.indexOf("(", t.indexOf(prop));
    return JSON.parse(t.slice(i + 1, t.lastIndexOf(")")));
};
const world = grab(path.join(data, "world/World.qml"), "property var world");
const clips = grab(path.join(data, "Sprites.qml"), "property var clips");
const days = Number(process.argv[3] || 3);
const from = Life.dayStart(process.argv[4] ? new Date(`${process.argv[4]}T12:00`) : new Date()).getTime() / 1000;
const until = from + days * 86400;
const STEP = 1 / 240;
const AFTER = 1e-4; // how far past the moment a screen's clock is set for

const cell = (clip, frame) => clips[clip] ? clips[clip].sequence[Math.min(frame, clips[clip].frames - 1)] : -1;
const sameSpot = (a, b) => a === b || (a !== null && b !== null && a.x === b.x && a.y === b.y && a.angle === b.angle);
const sameThread = (a, b) => a === b || (a !== null && b !== null && a.every((v, i) => v === b[i]));
const hornet = {
    name: "Hornet",
    at: t => Life.hornetAt(world, clips, t),
    next: t => Life.hornetChangesAt(world, clips, t),
    same: (a, b) => a === b || (a.clip === b.clip && cell(a.clip, a.frame) === cell(b.clip, b.frame) && a.x === b.x
        && a.y === b.y && a.facingRight === b.facingRight && a.scale === b.scale && a.angle === b.angle
        && sameSpot(a.needle, b.needle) && sameThread(a.thread, b.thread)),
};
const beast = {
    name: "the Bell Beast",
    still: true,
    at: t => Life.beastAt(world, clips, t),
    next: t => Life.beastNext(world, clips, t),
    same: (a, b) => a.clip === b.clip && cell(a.clip, a.frame) === cell(b.clip, b.frame),
};

let failed = 0;
for (const who of [hornet, beast]) {
    let asked = from; // when it last asked
    let shown = who.at(asked);
    let next = who.next(asked);
    let moments = 0;
    let moving = 0;
    let early = 0;
    for (let k = 1; from + k * STEP < until; k++) {
        const t = from + k * STEP;
        while (next > asked && next + AFTER <= t) {
            asked = next + AFTER;
            shown = who.at(asked);
            next = who.next(asked);
            moments++;
        }
        if (next <= asked) {
            // Moving: drawn on every frame.
            moving++;
            asked = t;
            shown = who.at(t);
            next = who.next(t);
            continue;
        }
        // A change at the moment itself is drawn just after it.
        const now = who.at(t);
        if (t < next - 1e-5 && !who.same(shown, now)) {
            early++;
            if (early <= 5) {
                console.log(`${who.name}: changes at ${new Date(t * 1000).toTimeString().slice(0, 8)} (+${(t % 1).toFixed(4)}), `
                    + `${((next - t) * 1000).toFixed(1)} ms before the moment given: `
                    + `${shown.clip} ${shown.frame} -> ${now.clip} ${now.frame}`);
            }
            shown = now;
        }
    }
    const perDay = n => Math.round(n / days);
    console.log(`${who.name}: ${perDay(moments)} moments a day, ${(moving * STEP / 3600 / days).toFixed(2)} h a day `
        + `moving (every frame), ${early} early changes`);
    failed += early + (who.still ? moving : 0);
}
console.log(`against ${86400 * 60} frames a day at 60 fps`);
process.exit(failed ? 1 : 0);
