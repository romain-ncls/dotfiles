#!/bin/sh
# Hyprland in a window of the Plasma session, with this repo's config and a
# D-Bus session bus of its own, so that its notifications and tray don't
# take Plasma's. KWin keeps its own shortcuts while the window has focus:
# try those binds with hyprctl (hyprctl -i 0 …). Extra arguments go to
# Hyprland.
here=$(dirname "$(realpath "$0")")
export HYPR_DEV=nested
exec dbus-run-session Hyprland --config "$here/../hypr/hyprland.lua" "$@"
