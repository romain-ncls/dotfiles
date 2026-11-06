// Brave's new tab: islands of links over Backdrop's wallpaper, in
// the session's colors. It's an unpacked extension (docs/manual-steps.md).
// Brave serves an unpacked extension's files through symbolic links wherever
// they point, so the hook link-data links in what the page reads:
//   links.js    the links: ~/.config/new-tab/links.js, private (names of
//               servers and clients), kept with the backups
//   backdrop/   Backdrop's state.json: the current wallpaper and its caption
//   lumar/      palette.json, the session's colors, when apply-lumar wrote one
//   tenants.json  the tenants a tenant field searches, from fetch-tenants:
//               { checked, tenants: [{ name, env, url }] }
//
// links.js exports the islands, in order:
//   export default [{ title, grid?, tenant?, links? }, …]
//   links:  [{ name, url, note? }]
//   grid:   the same pages on several environments, a row each:
//           { columns: ["App", …], icons?: true,
//             rows: [{ name, tone?, note?, urls: ["https://…", …] }] }
//           ("" leaves a cell empty; icons: true shows each cell's favicon)
//   tenant: a field for a tenant: [{ name, url: "https://host/{tenant}/", tone? }]
//           It searches tenants.json (arrows, Enter; Ctrl+Enter: a new tab).
//           A name not in the list, or any without one, opens on each host
//           (Enter: the first). The last tenants opened are kept.
// A tone colors an environment: prod, preprod, demo or dev. By default it's
// the row's or the host's name.

const tones = { prod: "red", preprod: "yellow", demo: "blue", dev: "green" };
const toneOf = (name, tone) => tones[tone ?? name] ?? "accent";

const $ = (id) => document.getElementById(id);

// h builds an element: h("a", { class: "link", href }, child, …).
function h(tag, props = {}, ...children) {
	const e = document.createElement(tag);
	for (const [k, v] of Object.entries(props)) {
		if (v == null || v === false) continue;
		if (k === "class") e.className = v;
		else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
		else e.setAttribute(k, v === true ? "" : v);
	}
	e.append(...children.flat(Infinity).filter((c) => c != null && c !== false && c !== ""));
	return e;
}

async function readJSON(path) {
	try {
		const r = await fetch(path, { cache: "no-store" });
		return r.ok ? await r.json() : null;
	} catch {
		return null;
	}
}

// Brave's own favicon cache: no request leaves the machine, and a site
// never visited gets Brave's globe.
function favicon(url, size = 32) {
	const u = new URL(chrome.runtime.getURL("/_favicon/"));
	u.searchParams.set("pageUrl", url);
	u.searchParams.set("size", String(size));
	return u.href;
}

// A favicon is shown as it is, on the glass, unless its pixels say
// otherwise (the favicons come from the extension's origin, so a canvas reads
// them):
//   none    Brave has none, only its globe: the link's initial instead
//   square  it fills its square to the corners: rounded like the rest
//   dark    a dark shape on nothing, lost on the glass: on a light tile
async function pixels(src) {
	const img = new Image();
	img.src = src;
	await img.decode();
	const g = new OffscreenCanvas(32, 32).getContext("2d", { willReadFrequently: true });
	g.drawImage(img, 0, 0, 32, 32);
	return g.getImageData(0, 0, 32, 32).data;
}
let globe;
async function faviconKind(src) {
	globe ??= pixels(favicon("https://new-tab.invalid/"));
	const [d, g] = await Promise.all([pixels(src), globe]);
	if (d.every((v, i) => v === g[i])) return "none";
	const opaque = (x, y) => d[(y * 32 + x) * 4 + 3] > 200;
	if (opaque(1, 1) && opaque(30, 1) && opaque(1, 30) && opaque(30, 30)) return "square";
	// How bright its colors are (HSV's value: a vivid red shows on the
	// glass as well as white does), weighed by how opaque.
	let value = 0, weight = 0;
	for (let i = 0; i < d.length; i += 4) {
		value += Math.max(d[i], d[i + 1], d[i + 2]) / 255 * d[i + 3];
		weight += d[i + 3];
	}
	return weight && value / weight < 0.4 ? "dark" : "";
}

function icon(url, name) {
	const src = favicon(url);
	const e = h("span", { class: "icon" });
	faviconKind(src).then((kind) => {
		e.append(kind === "none" ? h("span", { class: "initial" }, name.trim().charAt(0)) : h("img", { src, alt: "" }));
		if (kind) e.classList.add(kind);
	}, () => e.append(h("img", { src, alt: "" })));
	return e;
}

// The clock, to the minute.
const timeFormat = new Intl.DateTimeFormat(undefined, { hour: "2-digit", minute: "2-digit", hourCycle: "h23" });
const dateFormat = new Intl.DateTimeFormat(undefined, { weekday: "long", day: "numeric", month: "long" });
function tick() {
	const now = new Date();
	$("time").textContent = timeFormat.format(now);
	$("time").dateTime = now.toISOString();
	$("date").textContent = dateFormat.format(now);
	setTimeout(tick, 60_000 - (now.getSeconds() * 1000 + now.getMilliseconds()) + 20);
}

// The palette's keys become CSS variables: accentText is --accent-text.
function applyPalette(palette) {
	for (const [k, v] of Object.entries(palette ?? {})) {
		if (typeof v === "string" && /^#[0-9a-f]{6}$/i.test(v)) {
			document.documentElement.style.setProperty("--" + k.replace(/[A-Z]/g, (c) => "-" + c.toLowerCase()), v);
		}
	}
}

// The wallpaper. Backdrop's pictures are large (a progressive 4K JPEG takes
// 160 ms to decode), so the first tab to show one keeps two copies of it:
// one the size of the screen, in the page's cache, which the next tabs
// decode in 10 ms, and a small preview, which first-paint.js shows from the
// first frame. The picture fades in only when it took a while.
const wallKey = "new-tab.wall";
const wallCache = "new-tab.wall";

// The screen in device pixels (or the window, should it be larger): what a
// copy of the picture has to cover.
function screenSize() {
	return [
		Math.round(Math.max(screen.width, innerWidth) * devicePixelRatio),
		Math.round(Math.max(screen.height, innerHeight) * devicePixelRatio),
	];
}

// The picture at another size, well resampled, on a canvas.
async function resized(img, width, height) {
	const bitmap = await createImageBitmap(img, { resizeWidth: width, resizeHeight: height, resizeQuality: "high" });
	const canvas = h("canvas", { width, height });
	canvas.getContext("2d").drawImage(bitmap, 0, 0);
	bitmap.close();
	return canvas;
}

// Keeps the picture just shown for the next tabs: its preview, and when it
// came from Backdrop's file, its copy the size of the screen (its own size
// on a larger screen), in place of the last picture's.
async function keepCopies(img, name, cache, key, makeCopy) {
	const iw = img.naturalWidth, ih = img.naturalHeight;
	if (makeCopy && cache) {
		const [sw, sh] = screenSize();
		const scale = Math.min(1, Math.max(sw / iw, sh / ih));
		const canvas = await resized(img, Math.round(iw * scale), Math.round(ih * scale));
		const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 0.92));
		for (const old of await cache.keys()) await cache.delete(old);
		await cache.put(key, new Response(blob, { headers: { "x-screen": `${sw}x${sh}` } }));
	}
	const preview = (await resized(img, 320, Math.round(320 * ih / iw))).toDataURL("image/jpeg", 0.8);
	localStorage.setItem(wallKey, JSON.stringify({ file: name, preview }));
}

async function wallpaper() {
	const current = (await readJSON("backdrop/state.json"))?.current;
	if (!current?.file) return;
	const name = current.file.split("/").pop();
	const start = performance.now();
	// A copy made for a screen at least as large as this one.
	const key = "https://new-tab.invalid/wall/" + encodeURIComponent(name);
	const cache = await caches.open(wallCache).catch(() => null);
	const copy = await cache?.match(key).catch(() => null);
	const [cw, ch] = (copy?.headers.get("x-screen") ?? "0x0").split("x").map(Number);
	const [sw, sh] = screenSize();
	const fits = cw >= sw && ch >= sh;
	const img = new Image();
	img.alt = "";
	img.src = fits ? URL.createObjectURL(await copy.blob()) : "backdrop/current/" + encodeURIComponent(name);
	try {
		await img.decode();
	} catch {
		if (fits) cache.delete(key); // a broken copy: the next tab makes another
		return;
	}
	$("wall").classList.toggle("fade", performance.now() - start > 60);
	$("wall").append(img);
	if (fits) URL.revokeObjectURL(img.src);
	let kept = null;
	try {
		kept = JSON.parse(localStorage.getItem(wallKey));
	} catch {}
	if (!fits || kept?.file !== name) requestIdleCallback(() => keepCopies(img, name, cache, key, !fits));
	const lines = [h("strong", {}, current.title), h("span", {}, current.place), h("small", {}, current.credit)];
	$("caption").append(current.infoUrl ? h("a", { href: current.infoUrl }, lines) : h("div", {}, lines));
}

function links(list) {
	return h("ul", { class: "links" }, list.map((l) =>
		h("li", {}, h("a", { class: "link", href: l.url, title: l.url },
			icon(l.url, l.name),
			h("span", { class: "name" }, l.name),
			l.note && h("span", { class: "note" }, l.note)))));
}

function grid(g) {
	const columns = g.columns ?? [];
	return h("div", { class: "grid", style: `--columns: ${columns.length}` }, g.rows.map((row) => {
		const tone = `tone-${toneOf(row.name, row.tone)}`;
		return [
			h("span", { class: `env ${tone}`, title: row.note }, row.name),
			columns.map((label, i) => {
				const url = row.urls?.[i];
				if (!url) return h("span");
				return h("a", { class: `cell ${tone}`, href: url, title: url },
					g.icons && icon(url, label), label);
			}),
		];
	}));
}

// The tenants opened last: { name, env, url }.
const recentKey = "new-tab.recent";
function recentTenants() {
	try {
		const list = JSON.parse(localStorage.getItem(recentKey));
		return Array.isArray(list) ? list.filter((t) => typeof t?.url === "string") : [];
	} catch {
		return [];
	}
}
function remember(t) {
	try {
		localStorage.setItem(recentKey, JSON.stringify([t, ...recentTenants().filter((x) => x.url !== t.url)].slice(0, 6)));
	} catch {}
}

// The tenants whose name has q: the name itself first, then those it
// starts, then those with q after a dash; prod before the others.
function search(tenants, q) {
	q = q.toLowerCase();
	const found = [];
	for (const t of tenants) {
		const name = t.name.toLowerCase();
		const at = name.indexOf(q);
		if (at < 0) continue;
		const rank = name === q ? 0 : at === 0 ? 1 : /[^a-z0-9]/.test(name[at - 1]) ? 2 : 3;
		found.push({ t, key: [rank, t.env === "prod" ? 0 : 1, name.length, name, t.env] });
	}
	found.sort((a, b) => {
		const i = a.key.findIndex((k, i) => k !== b.key[i]);
		return i < 0 ? 0 : a.key[i] < b.key[i] ? -1 : 1;
	});
	return found.slice(0, 7).map((f) => f.t);
}

function tenant(hosts, list) {
	const known = (list?.tenants ?? []).filter((t) => t?.name && t?.url);
	const input = h("input", {
		type: "text",
		spellcheck: "false",
		autocomplete: "off",
		role: "combobox",
		"aria-label": "Tenant",
		placeholder: known.length ? `Search ${known.length} tenants` : "Tenant",
		title: list?.checked && `The tenant list, checked ${new Date(list.checked).toLocaleString()}`,
	});
	// mousedown would take the focus from the field, and blurring it hides
	// the results before the click lands
	const results = h("div", { class: "results", role: "listbox", hidden: true, onmousedown: (e) => e.preventDefault() });
	const anchors = hosts.map((x) => h("a", { class: `host tone-${toneOf(x.name, x.tone)}` }, x.name));
	const onHosts = h("div", { class: "hosts" }, anchors);
	const recent = h("div", { class: "recent" });
	const query = () => input.value.trim().replace(/^\/+|\/+$/g, "");
	let shown = [];
	let active = 0;

	// a name typed: the tenant on each host
	const typed = (i) => ({ name: query(), env: hosts[i].name, url: hosts[i].url.replaceAll("{tenant}", encodeURIComponent(query())) });

	function open(t, newTab) {
		remember(t);
		if (newTab) {
			window.open(t.url);
			showRecent();
		} else location.href = t.url;
	}
	function mark() {
		[...results.children].forEach((r, i) => r.classList.toggle("active", i === active));
	}
	function result(t, q, i) {
		const at = t.name.toLowerCase().indexOf(q.toLowerCase());
		return h("a", {
			class: "result",
			role: "option",
			href: t.url,
			title: t.url,
			onmouseenter: () => { active = i; mark(); },
			onclick: () => remember(t),
			onauxclick: () => remember(t),
		},
			h("span", { class: "tenant-name" }, t.name.slice(0, at), h("mark", {}, t.name.slice(at, at + q.length)), t.name.slice(at + q.length)),
			h("span", { class: `env tone-${toneOf(t.env)}` }, t.env),
			h("span", { class: "tenant-host" }, new URL(t.url).host));
	}
	function update() {
		const q = query();
		shown = q && known.length ? search(known, q) : [];
		active = 0;
		results.replaceChildren(...shown.map((t, i) => result(t, q, i)));
		results.hidden = !shown.length || document.activeElement !== input;
		onHosts.hidden = known.length > 0 && (!q || shown.length > 0);
		anchors.forEach((a, i) => {
			if (q) {
				a.href = typed(i).url;
				a.removeAttribute("aria-disabled");
			} else {
				a.removeAttribute("href");
				a.setAttribute("aria-disabled", "true");
			}
		});
		mark();
	}
	function showRecent() {
		recent.replaceChildren(...recentTenants().map((t) =>
			h("a", { href: t.url, title: t.url, onclick: () => remember(t), onauxclick: () => remember(t) },
				h("span", { class: "chip-name" }, t.name), h("span", { class: `chip-env tone-${toneOf(t.env)}` }, t.env))));
	}

	anchors.forEach((a, i) => {
		a.addEventListener("click", () => remember(typed(i)));
		a.addEventListener("auxclick", () => remember(typed(i)));
	});
	input.addEventListener("input", update);
	input.addEventListener("focus", () => { results.hidden = !shown.length; });
	input.addEventListener("blur", () => { results.hidden = true; });
	input.addEventListener("keydown", (e) => {
		if ((e.key === "ArrowDown" || e.key === "ArrowUp") && shown.length) {
			e.preventDefault();
			active = (active + (e.key === "ArrowDown" ? 1 : shown.length - 1)) % shown.length;
			mark();
		} else if (e.key === "Escape") {
			input.value = "";
			update();
		} else if (e.key === "Enter") {
			const t = shown[active] ?? (query() && hosts.length ? typed(0) : null);
			if (t) open(t, e.ctrlKey || e.metaKey);
		}
	});
	update();
	showRecent();
	return h("div", { class: "tenant" }, h("div", { class: "search" }, input, results), onHosts, recent);
}

function island(def, tenants) {
	try {
		return h("section", { class: "island" },
			def.title && h("h2", {}, def.title),
			def.grid && grid(def.grid),
			def.tenant && tenant(def.tenant, tenants),
			def.links?.length && links(def.links));
	} catch (e) {
		return notice(`The island “${def?.title ?? "?"}” in links.js: ${e.message}`);
	}
}

function notice(...lines) {
	return h("section", { class: "island notice" }, h("h2", {}, "New tab"), lines.map((l) => h("p", {}, l)));
}

async function loadIslands(tenants) {
	try {
		const { default: list } = await import(`./links.js?${Date.now()}`);
		if (!Array.isArray(list)) return [notice("links.js should export an array of islands: export default [ … ]")];
		return list.map((def) => island(def, tenants));
	} catch (e) {
		const where = h("code", {}, "~/.config/new-tab/links.js");
		return [e instanceof SyntaxError
			? notice(h("span", {}, where, ": ", e.message))
			: notice(h("span", {}, "No links yet: write them in ", where, "."),
				"The format is at the top of newtab.js, in the dotfiles' modules/new-tab.")];
	}
}
// Masonry: each island goes to the shortest column, in order, as many
// columns as fit.
function masonry(container, islands) {
	const min = 320;
	let count = 0;
	const layout = () => {
		const gap = parseFloat(getComputedStyle(container).columnGap) || 0;
		const n = Math.max(1, Math.min(islands.length, Math.floor((container.clientWidth + gap) / (min + gap))));
		if (n === count) return;
		count = n;
		const columns = Array.from({ length: n }, () => h("div", { class: "column" }));
		container.replaceChildren(...columns);
		for (const isl of islands) {
			columns.reduce((a, b) => (b.offsetHeight < a.offsetHeight ? b : a)).append(isl);
		}
	};
	layout();
	new ResizeObserver(layout).observe(container);
}

tick();
const wallpaperShown = wallpaper();
const [palette, islands] = await Promise.all([readJSON("lumar/palette.json"), readJSON("tenants.json").then(loadIslands)]);
applyPalette(palette);
masonry($("islands"), islands);
await wallpaperShown;
