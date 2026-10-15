/*
 * Checks that two versions of Hornet's life (plasma/contents/ui/life.js) plan and show exactly
 * the same thing against the built world, without Plasma: for changes meant to make it cheaper,
 * not different.
 *
 *   git show HEAD:packages/silksong-wallpaper/plasma/contents/ui/life.js > REF_LIFE
 *   node tools/plan_identity.js REF_LIFE plasma/contents/ui/life.js [DAYS]
 *
 * Compares her day plans (segments, log, waking and bedtime), the Bell Beast's and the small
 * life's for DAYS days from today (40 by default) and on the days around the clock changes and
 * the ends of a month, a year and February; then what the screens ask for (her pose, the
 * beast's, the creatures', all or some of them, and the clips ahead) every 0.37 s through her
 * waking, midday, evening and another day, densely across 04:00, when one day hands over to the
 * next, and around every song and lilypad flight of three days, where the creatures change what
 * they do. Each version gets its own copy of the world and the clips, as each screen does, so
 * that a cache kept on a shared object shows. Exits with an error on any difference.
 */
const fs = require("fs");
const path = require("path");
const os = require("os");

const data = path.join(os.homedir(), ".local/share/silksong-wallpaper");
const NAMES = ["planDay", "planBeast", "planCritters", "dayStart", "hornetAt", "crittersAt", "beastAt", "clipsAhead",
    "beastClipsAhead", "critterClips"];
const load = file => {
    const src = fs.readFileSync(file, "utf8").replace(".pragma library", "");
    return new Function(src + `\nreturn { ${NAMES.join(", ")}, cacheOf: () => cache };`)();
};
const grab = (file, prop) => {
    const t = fs.readFileSync(file, "utf8");
    const i = t.indexOf("(", t.indexOf(prop));
    return JSON.parse(t.slice(i + 1, t.lastIndexOf(")")));
};
const copies = () => [grab(path.join(data, "world/World.qml"), "property var world"),
    grab(path.join(data, "Sprites.qml"), "property var clips")];

if (process.argv.length < 4) {
    console.log("usage: node tools/plan_identity.js REF_LIFE NEW_LIFE [DAYS]");
    process.exit(2);
}
const A = load(process.argv[2]);
const B = load(process.argv[3]);
const days = Number(process.argv[4] || 40);
const [worldA, clipsA] = copies();
const [worldB, clipsB] = copies();

// Deep equality, reporting the first difference.
function same(a, b, where) {
    if (a === b || (Number.isNaN(a) && Number.isNaN(b))) {
        return true;
    }
    if (typeof a !== "object" || typeof b !== "object" || a === null || b === null || Array.isArray(a) !== Array.isArray(b)) {
        console.log(`differs at ${where}: ${JSON.stringify(a)} | ${JSON.stringify(b)}`);
        return false;
    }
    const ka = Object.keys(a).filter(k => a[k] !== undefined);
    const kb = Object.keys(b).filter(k => b[k] !== undefined);
    const lone = ka.filter(k => b[k] === undefined).concat(kb.filter(k => a[k] === undefined));
    if (lone.length) {
        console.log(`differs at ${where}: ${lone.slice(0, 5).join(", ")} on one side only`);
        return false;
    }
    return ka.every(k => same(a[k], b[k], `${where}.${k}`));
}

// The plans.
const dates = [];
for (let d = 0; d < days; d++) {
    const when = new Date();
    when.setDate(when.getDate() + d);
    when.setHours(12, 0, 0, 0);
    dates.push(when);
}
for (const [y, m, d] of [[2026, 9, 25], [2026, 9, 31], [2026, 11, 31], [2027, 0, 1], [2027, 1, 28], [2027, 2, 27],
    [2027, 2, 28], [2028, 1, 29]]) {
    dates.push(new Date(y, m, d, 12));
}
let plans = 0;
let segments = 0;
for (const when of dates) {
    const start = A.dayStart(when);
    const key = start.getFullYear() * 10000 + (start.getMonth() + 1) * 100 + start.getDate();
    const day0 = start.getTime() / 1000;
    const pa = A.planDay(worldA, clipsA, day0, key);
    const pb = B.planDay(worldB, clipsB, day0, key);
    segments += pa.segments.length;
    if (!same(pa, pb, `${key} plan`)
        || !same(A.planBeast(worldA, clipsA, day0, key, pa), B.planBeast(worldB, clipsB, day0, key, pb), `${key} beast`)
        || !same(A.planCritters(worldA, clipsA, pa.segments), B.planCritters(worldB, clipsB, pb.segments), `${key} critters`)) {
        plans++;
    }
}
console.log(`plans: ${dates.length} days, ${segments} segments, ${plans} days differ`);

// What the screens ask for, one moment at a time.
let samples = 0;
let wrong = 0;
function compare(t, ahead) {
    samples++;
    const ok = same(A.hornetAt(worldA, clipsA, t), B.hornetAt(worldB, clipsB, t), `hornetAt ${t}`)
        && same(A.crittersAt(worldA, clipsA, t), B.crittersAt(worldB, clipsB, t), `crittersAt ${t}`)
        && same(A.crittersAt(worldA, clipsA, t, worldA.critters.slice(3, 9)),
            B.crittersAt(worldB, clipsB, t, worldB.critters.slice(3, 9)), `crittersAt (some) ${t}`)
        && same(A.beastAt(worldA, clipsA, t), B.beastAt(worldB, clipsB, t), `beastAt ${t}`)
        && (!ahead || (same(A.clipsAhead(worldA, clipsA, t, 45), B.clipsAhead(worldB, clipsB, t, 45), `clipsAhead ${t}`)
            && same(A.beastClipsAhead(worldA, clipsA, t, 45), B.beastClipsAhead(worldB, clipsB, t, 45), `beastClipsAhead ${t}`)
            && same(A.critterClips(clipsA, worldA.critters), B.critterClips(clipsB, worldB.critters), "critterClips")));
    if (!ok) {
        wrong++;
    }
}
const day = A.dayStart(new Date()).getTime() / 1000; // 04:00 today
const ranges = [
    [day + 3 * 3600 - 120, day + 3 * 3600 + 5400, 0.37], // her waking
    [day + 8 * 3600, day + 9 * 3600 + 900, 0.37], // midday, with the 13:00 song
    [day + 16 * 3600 + 3000, day + 17 * 3600 + 600, 0.37], // the evening needolin, the 21:00 song
    [day + 24 * 3600 - 60, day + 24 * 3600 + 60, 0.05], // 04:00, the next day
    [day + 1.5 * 86400, day + 1.5 * 86400 + 600, 0.1], // another day
];
let n = 0;
for (const [from, until, step] of ranges) {
    for (let t = from; t < until && wrong <= 5; t += step) {
        compare(t, n++ % 13 === 0);
    }
}
// Around every song and lilypad flight, where the creatures change what they do.
for (let d = 0; d < 3 && wrong <= 5; d++) {
    A.crittersAt(worldA, clipsA, day + d * 86400 + 8 * 3600);
    const plan = A.cacheOf().critters;
    const around = [];
    for (const s of plan.songs) {
        around.push([s[0] - 0.5, s[0] + 0.5], [s[1] - 0.5, s[1] + 0.5]);
    }
    for (const f of Object.values(plan.flights).flat()) {
        around.push([f.t0 - 0.3, f.t0 + 0.3], [f.t1 - 0.3, f.t1 + 0.3]);
    }
    for (const [from, until] of around) {
        for (let t = from; t < until && wrong <= 5; t += 0.0173) {
            compare(t, false);
        }
        if (wrong <= 5) {
            compare((from + until) / 2, false); // the change itself
        }
    }
}
console.log(`moments: ${samples} compared, ${wrong} differ`);
process.exit(plans || wrong ? 1 : 0);
