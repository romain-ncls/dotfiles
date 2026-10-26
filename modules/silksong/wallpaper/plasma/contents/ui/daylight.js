/*
 * Time of day for the scene: a veil drawn over everything (colour + opacity)
 * and how strongly the baked lights (lanterns, candles, glows) shine through it.
 *
 * Keyframes are placed relative to the real sunrise and sunset for the date
 * and place, so evenings come earlier in winter; or at set hours (the
 * NightUntil, DayFrom, DayUntil and NightFrom settings).
 */
.pragma library

const DEG = Math.PI / 180;

// The night's veil, from after dusk until an hour before sunrise.
const night = { color: [0.04, 0.07, 0.17], opacity: 0.58, lights: 1.0 };

// The day's sun and keyframes as last worked out: they change once a day, the lighting is asked
// for on every tick.
let last = { year: NaN, day: NaN, offset: NaN, latitude: NaN, longitude: NaN, hours: null, sun: null, keys: null, night: null };

// Sunrise and sunset in local hours (NOAA's simplified solar position).
function sunTimes(date, latitude, longitude) {
    const start = new Date(date.getFullYear(), 0, 0);
    const day = Math.floor((date - start) / 86400000);
    const g = 2 * Math.PI / 365 * (day - 1);
    const eqTime = 229.18 * (0.000075 + 0.001868 * Math.cos(g) - 0.032077 * Math.sin(g)
        - 0.014615 * Math.cos(2 * g) - 0.040849 * Math.sin(2 * g)); // minutes
    const decl = 0.006918 - 0.399912 * Math.cos(g) + 0.070257 * Math.sin(g) - 0.006758 * Math.cos(2 * g)
        + 0.000907 * Math.sin(2 * g) - 0.002697 * Math.cos(3 * g) + 0.00148 * Math.sin(3 * g);
    const cosH = (Math.cos(90.833 * DEG) - Math.sin(latitude * DEG) * Math.sin(decl))
        / (Math.cos(latitude * DEG) * Math.cos(decl));
    const h = Math.acos(Math.max(-1, Math.min(1, cosH))) / DEG; // degrees
    const utcOffset = -date.getTimezoneOffset() / 60;
    const noon = 12 - longitude / 15 - eqTime / 60 + utcOffset;
    return { sunrise: noon - h / 15, sunset: noon + h / 15 };
}

// "HH:MM" in hours, or null.
function hours(text) {
    const m = /^\s*(\d{1,2}):(\d{2})\s*$/.exec(text || "");
    return m ? Number(m[1]) + Number(m[2]) / 60 : null;
}

function mix(a, b, t) {
    return a + (b - a) * t;
}

function mixColor(a, b, t) {
    return [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
}

// The day's keyframes: night until `until`, dawn until first light at `light`, the day's colours
// up to its golden hour at `golden`, dusk, night from `dark` (the day's colours drawn closer
// together on a day shorter than 5 hours, so that they stay in order).
function keyframes(t) {
    const k = Math.min(1, (t.golden - t.light) / 5.0);
    return [
        { at: t.until, color: night.color, opacity: night.opacity, lights: night.lights },
        { at: t.light, color: [0.62, 0.40, 0.50], opacity: 0.16, lights: 0.5 },             // first light, rosy
        { at: t.light + 1.0 * k, color: [1.0, 0.78, 0.55], opacity: 0.05, lights: 0.1 },    // warm morning
        { at: t.light + 2.5 * k, color: [0.70, 0.86, 1.0], opacity: 0.05, lights: 0.0 },    // cool, clear
        { at: t.noon, color: [1.0, 1.0, 1.0], opacity: 0.0, lights: 0.0 },                   // neutral
        { at: t.golden - 1.3 * k, color: [1.0, 0.85, 0.55], opacity: 0.06, lights: 0.0 },   // warmer afternoon
        { at: t.golden, color: [1.0, 0.66, 0.30], opacity: 0.10, lights: 0.25 },             // golden hour
        { at: t.golden + (t.dark - t.golden) / 1.9, color: [0.36, 0.24, 0.46], opacity: 0.30, lights: 0.7 }, // dusk
        { at: t.dark, color: night.color, opacity: night.opacity, lights: night.lights },
    ];
}

// The keyframes' hours: from the sun (night until an hour before sunrise, first light at
// sunrise, golden hour 0.7 hours before sunset, night 1.2 hours after), or set (["HH:MM"] x 4:
// night until, day from, day until, night from; used when all four are there and in order).
function dayHours(sun, set) {
    const h = (set || []).map(hours);
    if (h.length === 4 && h.every(v => v !== null) && h[0] < h[1] && h[1] < h[2] && h[2] < h[3]) {
        return { until: h[0], light: h[1], noon: (h[1] + h[2]) / 2, golden: h[2], dark: h[3] };
    }
    return { until: sun.sunrise - 1.0, light: sun.sunrise, noon: (sun.sunrise + sun.sunset) / 2, golden: sun.sunset - 0.7,
             dark: sun.sunset + 1.2 };
}

// Veil colour (0-1 RGB), its opacity, and the lights' strength (0-1) at a moment; with `set`
// hours (dayHours), at those instead of the sun's.
function lightingAt(date, latitude, longitude, set) {
    // The sun only changes with the day of the year as sunTimes counts it (one behind the date
    // just after midnight in summer time), the time zone and the place: it and the day's keyframes
    // are worked out again only then.
    const year = date.getFullYear();
    const day = Math.floor((date - new Date(year, 0, 0)) / 86400000);
    const offset = date.getTimezoneOffset();
    const setKey = (set || []).join(",");
    if (year !== last.year || day !== last.day || offset !== last.offset || latitude !== last.latitude
        || longitude !== last.longitude || setKey !== last.hours) {
        const sun = sunTimes(date, latitude, longitude);
        last = { year: year, day: day, offset: offset, latitude: latitude, longitude: longitude, hours: setKey, sun: sun,
                 keys: keyframes(dayHours(sun, set)), night: null };
    }
    const sun = last.sun;
    const keys = last.keys;
    const hour = date.getHours() + date.getMinutes() / 60 + date.getSeconds() / 3600;
    if (hour <= keys[0].at || hour >= keys[keys.length - 1].at) {
        // The same object all night, so that what's bound to it isn't worked out again every tick.
        last.night = last.night || { color: night.color, opacity: night.opacity, lights: night.lights, sun: sun };
        return last.night;
    }
    for (let i = 1; i < keys.length; i++) {
        if (hour <= keys[i].at) {
            const a = keys[i - 1];
            const b = keys[i];
            const t = (hour - a.at) / Math.max(1e-6, b.at - a.at);
            const s = t * t * (3 - 2 * t); // ease in and out
            return {
                color: mixColor(a.color, b.color, s),
                opacity: mix(a.opacity, b.opacity, s),
                lights: mix(a.lights, b.lights, s),
                sun: sun,
            };
        }
    }
    return { color: night.color, opacity: night.opacity, lights: night.lights, sun: sun };
}
