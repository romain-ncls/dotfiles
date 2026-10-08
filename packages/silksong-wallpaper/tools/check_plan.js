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
const Life = new Function(src + "\nreturn { planDay, planBeast, dayStart, pose };")();
const grab = (file, prop) => {
    const t = fs.readFileSync(file, "utf8");
    const i = t.indexOf("(", t.indexOf(prop));
    return JSON.parse(t.slice(i + 1, t.lastIndexOf(")")));
};
const world = grab(path.join(data, "world/World.qml"), "property var world");
const clips = grab(path.join(data, "Sprites.qml"), "property var clips");
const days = Number(process.argv[2] || 3);
const moving = ["walk", "line", "fall", "jump", "wallhop"];

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
for (const [k, v] of Object.entries(fastest)) {
    console.log(`fastest ${k}: ${v.toFixed(1)} units/s`);
}
console.log(`teleports: ${teleports}`);
process.exit(teleports ? 1 : 0);
