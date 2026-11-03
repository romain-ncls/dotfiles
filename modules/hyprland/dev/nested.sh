#!/bin/sh
# Hyprland in a window of the Plasma session, with this repo's config and a
# D-Bus session bus of its own, so that its notifications and tray don't
# take Plasma's. KWin keeps its own shortcuts while the window has focus:
# try those binds with hyprctl (hyprctl -i <its instance> …). Extra
# arguments go to Hyprland. HYPR_DEV_CONFIG: the hyprland.lua to try, as in
# headless.sh.
here=$(dirname "$(realpath "$0")")
export HYPR_DEV=nested
exec dbus-run-session Hyprland --config "${HYPR_DEV_CONFIG:-$here/../hypr/hyprland.lua}" "$@"
