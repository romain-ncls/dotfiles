/*
 * Time of day for the scene: a veil drawn over everything (colour + opacity)
 * and how strongly the baked lights (lanterns, candles, glows) shine through it.
 *
 * Keyframes are placed relative to the real sunrise and sunset for the date
 * and place, so evenings come earlier in winter.
 */
.pragma library

const DEG = Math.PI / 180;

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

function mix(a, b, t) {
    return a + (b - a) * t;
}

function mixColor(a, b, t) {
    return [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];
}

// Veil colour (0-1 RGB), its opacity, and the lights' strength (0-1) at a moment.
function lightingAt(date, latitude, longitude) {
    const sun = sunTimes(date, latitude, longitude);
    const hour = date.getHours() + date.getMinutes() / 60 + date.getSeconds() / 3600;
    const noon = (sun.sunrise + sun.sunset) / 2;
    const night = { color: [0.04, 0.07, 0.17], opacity: 0.58, lights: 1.0 };
    const keys = [
        { at: sun.sunrise - 1.0, color: night.color, opacity: night.opacity, lights: night.lights },
        { at: sun.sunrise, color: [0.62, 0.40, 0.50], opacity: 0.16, lights: 0.5 },        // first light, rosy
        { at: sun.sunrise + 1.0, color: [1.0, 0.78, 0.55], opacity: 0.05, lights: 0.1 },   // warm morning
        { at: sun.sunrise + 2.5, color: [0.70, 0.86, 1.0], opacity: 0.05, lights: 0.0 },   // cool, clear
        { at: noon, color: [1.0, 1.0, 1.0], opacity: 0.0, lights: 0.0 },                    // neutral
        { at: sun.sunset - 2.0, color: [1.0, 0.85, 0.55], opacity: 0.06, lights: 0.0 },    // warmer afternoon
        { at: sun.sunset - 0.7, color: [1.0, 0.66, 0.30], opacity: 0.10, lights: 0.25 },   // golden hour
        { at: sun.sunset + 0.3, color: [0.36, 0.24, 0.46], opacity: 0.30, lights: 0.7 },   // dusk
        { at: sun.sunset + 1.2, color: night.color, opacity: night.opacity, lights: night.lights },
    ];
    if (hour <= keys[0].at || hour >= keys[keys.length - 1].at) {
        return { color: night.color, opacity: night.opacity, lights: night.lights, sun: sun };
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
