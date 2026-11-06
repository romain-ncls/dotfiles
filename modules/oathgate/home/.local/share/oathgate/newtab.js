// Oathgate, Brave's new tab: islands of links over Backdrop's wallpaper, in
// the session's colors. It's an unpacked extension (docs/manual-steps.md).
// Brave serves an unpacked extension's files through symbolic links wherever
// they point, so the hook link-data links in what the page reads:
//   links.js    the links: ~/.config/oathgate/links.js, private (names of
//               servers and clients), kept with the backups
//   backdrop/   Backdrop's state.json: the current wallpaper and its caption
//   lumar/      palette.json, the session's colors, when apply-lumar wrote one
//
// links.js exports the islands, in order:
//   export default [{ title, grid?, tenant?, links? }, …]
//   links:  [{ name, url, note? }]
//   grid:   the same pages on several environments, a row each:
//           { columns: ["App", …], icons?: true,
//             rows: [{ name, tone?, note?, urls: ["https://…", …] }] }
//           ("" leaves a cell empty; icons: true shows each cell's favicon)
//   tenant: a field for a tenant, opened on each host:
//           [{ name, url: "https://host/{tenant}/", tone? }]
//           (Enter opens the first host; the last tenants are kept)
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
// never visited gets the default icon.
function favicon(url, size = 32) {
	const u = new URL(chrome.runtime.getURL("/_favicon/"));
	u.searchParams.set("pageUrl", url);
	u.searchParams.set("size", String(size));
	return u.href;
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

// The wallpaper fades in only when it took a while: a picture already
// decoded for another tab shows at once.
async function wallpaper() {
	const current = (await readJSON("backdrop/state.json"))?.current;
	if (!current?.file) return;
	const img = new Image();
	img.alt = "";
	img.src = "backdrop/current/" + encodeURIComponent(current.file.split("/").pop());
	const start = performance.now();
	try {
		await img.decode();
	} catch {
		return;
	}
	$("wall").classList.toggle("fade", performance.now() - start > 60);
	$("wall").append(img);
	const lines = [h("strong", {}, current.title), h("span", {}, current.place), h("small", {}, current.credit)];
	$("caption").append(current.infoUrl ? h("a", { href: current.infoUrl }, lines) : h("div", {}, lines));
}

function links(list) {
	return h("ul", { class: "links" }, list.map((l) =>
		h("li", {}, h("a", { class: "link", href: l.url, title: l.url },
			h("span", { class: "icon" }, h("img", { src: favicon(l.url), alt: "" })),
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
					g.icons && h("img", { src: favicon(url), alt: "" }), label);
			}),
		];
	}));
}

const recentKey = "oathgate.tenants";
function recentTenants() {
	try {
		const list = JSON.parse(localStorage.getItem(recentKey));
		return Array.isArray(list) ? list : [];
	} catch {
		return [];
	}
}

function tenant(hosts) {
	const input = h("input", { type: "text", placeholder: "Tenant", "aria-label": "Tenant", spellcheck: "false", autocomplete: "off" });
	const anchors = hosts.map((x) => h("a", { class: `host tone-${toneOf(x.name, x.tone)}` }, x.name));
	const recent = h("div", { class: "recent" });
	const name = () => input.value.trim().replace(/^\/+|\/+$/g, "");

	function update() {
		const t = name();
		anchors.forEach((a, i) => {
			if (t) {
				a.href = hosts[i].url.replaceAll("{tenant}", encodeURIComponent(t));
				a.removeAttribute("aria-disabled");
			} else {
				a.removeAttribute("href");
				a.setAttribute("aria-disabled", "true");
			}
		});
	}
	function remember() {
		const t = name();
		if (!t) return;
		try {
			localStorage.setItem(recentKey, JSON.stringify([t, ...recentTenants().filter((x) => x !== t)].slice(0, 6)));
		} catch {}
	}
	function showRecent() {
		recent.replaceChildren(...recentTenants().map((t) =>
			h("button", { type: "button", onclick: () => { input.value = t; update(); input.focus(); } }, t)));
	}

	for (const a of anchors) {
		a.addEventListener("click", remember);
		a.addEventListener("auxclick", remember);
	}
	input.addEventListener("input", update);
	input.addEventListener("keydown", (e) => {
		const href = anchors[0]?.getAttribute("href");
		if (e.key !== "Enter" || !href) return;
		remember();
		if (e.ctrlKey || e.metaKey) {
			window.open(href);
			showRecent();
		} else location.href = href;
	});
	update();
	showRecent();
	return h("div", { class: "tenant" }, input, h("div", { class: "hosts" }, anchors), recent);
}

function island(def) {
	try {
		return h("section", { class: "island" },
			def.title && h("h2", {}, def.title),
			def.grid && grid(def.grid),
			def.tenant && tenant(def.tenant),
			def.links?.length && links(def.links));
	} catch (e) {
		return notice(`The island “${def?.title ?? "?"}” in links.js: ${e.message}`);
	}
}

function notice(...lines) {
	return h("section", { class: "island notice" }, h("h2", {}, "Oathgate"), lines.map((l) => h("p", {}, l)));
}

async function loadIslands() {
	try {
		const { default: list } = await import(`./links.js?${Date.now()}`);
		if (!Array.isArray(list)) return [notice("links.js should export an array of islands: export default [ … ]")];
		return list.map(island);
	} catch (e) {
		const where = h("code", {}, "~/.config/oathgate/links.js");
		return [e instanceof SyntaxError
			? notice(h("span", {}, where, ": ", e.message))
			: notice(h("span", {}, "No links yet: write them in ", where, "."),
				"The format is at the top of newtab.js, in the dotfiles' modules/oathgate.")];
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
const shown = wallpaper();
const [palette, islands] = await Promise.all([readJSON("lumar/palette.json"), loadIslands()]);
applyPalette(palette);
masonry($("islands"), islands);
await shown;
