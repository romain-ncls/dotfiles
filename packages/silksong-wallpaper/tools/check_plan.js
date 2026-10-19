/*
 * Checks Hornet's day plans (plasma/contents/ui/life.js) against the built world, without
 * Plasma:
 *
 *   node tools/check_plan.js [DAYS]
 *
 * For DAYS days from today: every place where her position jumps between one segment and the
 * next (a teleport), the Bell Beast's day (back to back, with clips that exist), and her
 * fastest speed inside each kind of move, sampled at 60 fps (walks
 * stay near 5 units/s, falls at 30, the Clawline dash at 32). Exits with an error on a
 * teleport. The house animations and the bench sit on their own pivots, a few millimetres from
 * where she stands: those aren't counted.
 */
const fs = require("fs");
const path = require("path");
const os = require("os");

const root = path.join(__dirname, "..");
const data = path.join(os.homedir(), ".local/share/silksong-wallpaper");
const src = fs.readFileSync(path.join(root, "plasma/contents/ui/life.js"), "utf8").replace(".pragma library", "");
const Life = new Function(src + "\nreturn { planDay, planBeast, dayStart, pose, crittersAt, daySegments, cacheOf: () => cache };")();
const grab = (file, prop) => {
    const t = fs.readFileSync(file, "utf8");
    const i = t.indexOf("(", t.indexOf(prop));
    return JSON.parse(t.slice(i + 1, t.lastIndexOf(")")));
};
const world = grab(path.join(data, "world/World.qml"), "property var world");
const clips = grab(path.join(data, "Sprites.qml"), "property var clips");
const days = Number(process.argv[2] || 3);
const moving = ["walk", "line", "fall", "jump", "wallhop", "glide", "wallslide"];

let teleports = 0;
const fastest = {};
for (let d = 0; d < days; d++) {
    const when = new Date();
    when.setDate(when.getDate() + d);
    const start = Life.dayStart(when);
    const key = start.getFullYear() * 10000 + (start.getMonth() + 1) * 100 + start.getDate();
    const plan = Life.planDay(world, clips, start.getTime() / 1000, key);
    const segs = plan.segments;
    // The Bell Beast's day: back to back, with clips that exist.
    const beast = Life.planBeast(world, clips, start.getTime() / 1000, key, plan);
    for (let i = 0; i < beast.length; i++) {
        const b = beast[i];
        if (!clips[b.clip] || b.t1 < b.t0 || (i > 0 && Math.abs(b.t0 - beast[i - 1].t1) > 1e-6)) {
            teleports++;
            console.log(`Bell Beast: bad segment ${b.clip} ${b.t0}-${b.t1}`);
        }
    }
    const sings = beast.filter(b => b.clip.indexOf("Sing End") >= 0).length;
    const visits = plan.log.filter(v => v.id === "bell_beast").length;
    for (let i = 0; i + 1 < segs.length; i++) {
        const a = segs[i], b = segs[i + 1];
        const pa = Life.pose(world, clips, a, a.t1 - 1e-4);
        const pb = Life.pose(world, clips, b, b.t0);
        const gap = Math.hypot(pa.x - pb.x, pa.y - pb.y);
        const anchored = /Sit|Desk|Lay/.test(a.clip + b.clip) && Math.abs(pa.x - pb.x) < 0.01 && gap <= 0.31;
        if (gap > 0.15 && !anchored) {
            teleports++;
            console.log(`teleport ${gap.toFixed(2)}: ${a.kind} ${a.clip} (${pa.x.toFixed(1)}, ${pa.y.toFixed(1)}) -> `
                + `${b.kind} ${b.clip} (${pb.x.toFixed(1)}, ${pb.y.toFixed(1)}) at ${new Date(b.t0 * 1000).toTimeString().slice(0, 8)}`);
        }
    }
    if (d === 0) {
        for (const s of segs) {
            if (moving.indexOf(s.kind) < 0) {
                continue;
            }
            let prev = null;
            for (let t = s.t0; t <= s.t1; t += 1 / 60) {
                const p = Life.pose(world, clips, s, Math.min(t, s.t1 - 1e-4));
                if (prev) {
                    const v = Math.hypot(p.x - prev.x, p.y - prev.y) * 60;
                    const k = `${s.kind} ${s.clip}`;
                    fastest[k] = Math.max(fastest[k] || 0, v);
                }
                prev = p;
            }
        }
    }
    console.log(`day ${key}: ${segs.length} segments; Bell Beast: ${beast.length} segments, ${sings} songs, `
        + `Hornet visits it ${visits} times`);
}
// The small life: on the first day, lilypad flights and the songs it hears; every creature
// sampled at 30 fps around each song and flight (where it changes what it does) and through a
// quiet hour, for jumps in position (a teleport) or poses without a clip.
{
    const when = new Date();
    const start = Life.dayStart(when).getTime() / 1000;
    Life.crittersAt(world, clips, start + 6 * 3600);
    const plan = Life.cacheOf().critters;
    const flights = Object.values(plan.flights).reduce((n, f) => n + f.length, 0);
    console.log(`small life: ${(world.critters || []).length} creatures, ${plan.songs.length} songs heard, ${flights} lilypad flights`);
    const windows = [[start + 10 * 3600, start + 11 * 3600]];
    for (const s of plan.songs) {
        windows.push([s[0] - 2, s[0] + 4], [s[1] - 2, s[1] + 4]);
    }
    for (const f of Object.values(plan.flights).flat()) {
        windows.push([f.t0 - 1, f.t1 + 1]);
    }
    let jumps = 0;
    for (const [a, b] of windows) {
        let prev = null;
        for (let t = a; t < b; t += 1 / 30) {
            const now = Life.crittersAt(world, clips, t);
            if (now.length !== (world.critters || []).length || now.some(p => !isFinite(p.x) || !isFinite(p.y))) {
                jumps++;
                console.log(`small life: a creature without a pose at ${t}`);
            }
            if (prev) {
                now.forEach((p, i) => {
                    const d = Math.hypot(p.x - prev[i].x, p.y - prev[i].y);
                    if (d > 0.7) { // a dragonfly's dart: at most 3.6 units in 0.3 s, 0.6 in a frame
                        jumps++;
                        console.log(`small life: ${p.id} jumps ${d.toFixed(2)} at ${new Date(t * 1000).toTimeString().slice(0, 8)}`);
                    }
                });
            }
            prev = now;
        }
    }
    teleports += jumps;
}
for (const [k, v] of Object.entries(fastest)) {
    console.log(`fastest ${k}: ${v.toFixed(1)} units/s`);
}
console.log(`teleports: ${teleports}`);
process.exit(teleports ? 1 : 0);
