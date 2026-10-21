#!/bin/sh
# Makes Backdrop the wallpaper of every desktop. It needs Plasma running:
# without it, the hook fails and the next apply runs it again.
if [ -z "$WAYLAND_DISPLAY" ]; then
	echo "backdrop: run lodestar apply again from Plasma to set the wallpaper" >&2
	exit 1
fi
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
	'desktops().forEach(d => { d.wallpaperPlugin = "com.github.romain-ncls.backdrop"; });'
