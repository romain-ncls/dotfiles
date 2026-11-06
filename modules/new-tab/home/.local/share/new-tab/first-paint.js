// Before the first paint (a plain script in the head, which the page waits
// for): the wallpaper behind everything, from the copy newtab.js keeps in
// localStorage (the only storage read this early), so a new tab opens on
// the picture, in place, rather than on the dark background.
try {
	const image = localStorage.getItem("new-tab.wall.image");
	if (image?.startsWith("data:image/")) {
		document.documentElement.style.setProperty("--wall", `url("${image}")`);
	}
} catch {
	// No copy: the background until newtab.js shows Backdrop's file.
}
