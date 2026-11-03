#!/bin/sh
# Hyprland with no display, for checks and screenshots (grim, hyprctl -i 0).
# It runs in a user scope, outside the login session, so it finds no seat
# and doesn't try the screens Plasma holds; without WAYLAND_DISPLAY it
# doesn't open a window either, and only its headless outputs are left.
# The scope caps its memory (heavy jobs froze the machine before). Extra
# arguments go to Hyprland.
here=$(dirname "$(realpath "$0")")
exec systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 \
	env -u WAYLAND_DISPLAY -u DISPLAY HYPR_DEV=headless \
	dbus-run-session Hyprland --config "$here/../hypr/hyprland.lua" "$@"
