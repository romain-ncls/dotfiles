#!/bin/sh
# Makes Backdrop the wallpaper of every desktop that has another one; the
# others are left alone, so an apply with nothing to do changes nothing. It
# needs Plasma running: without it, the hook fails and the next apply runs it
# again.
if [ -z "$WAYLAND_DISPLAY" ]; then
	echo "backdrop: run lodestar apply again from Plasma to set the wallpaper" >&2
	exit 1
fi
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript '
const plugin = "com.github.romain-ncls.backdrop";
desktops().forEach(d => { if (d.wallpaperPlugin != plugin) d.wallpaperPlugin = plugin; });'
