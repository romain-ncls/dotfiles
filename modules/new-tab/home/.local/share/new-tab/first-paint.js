// Before the first paint (a plain script in the head, which the page waits
// for): a small preview of the wallpaper behind everything, so a new tab
// opens on the picture rather than on the dark background while newtab.js
// loads it. newtab.js keeps the preview, in localStorage, the only storage
// read this early.
try {
	const preview = JSON.parse(localStorage.getItem("new-tab.wall"))?.preview;
	if (preview?.startsWith("data:image/")) {
		document.documentElement.style.setProperty("--preview", `url("${preview}")`);
	}
} catch {
	// No preview: the background until the picture comes.
}
