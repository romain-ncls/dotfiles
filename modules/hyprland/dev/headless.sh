#!/bin/sh
# Hyprland with no display, for checks and screenshots: nested in an
# offscreen KWin (kwin_wayland --virtual), since Hyprland's own headless
# outputs need a backend with a GPU under them (the screens' or a parent
# compositor's). hyprctl -i <its instance> reaches it (hyprctl instances:
# the newest); HYPR_DEV=headless lets the config add headless outputs laid
# out like the desk. Everything runs in a user scope with a memory cap
# (heavy jobs froze the machine before) and its own D-Bus session bus; KWin's
# own lock screen off (it locked itself and drew the Silksong world unseen).
# Extra arguments go to Hyprland.
#
# HYPR_DEV_CONFIG: the hyprland.lua to try, default this repo's. Try changes
# on a copy: ~/.config/hypr is the repo's folder, and the live session
# reloads as soon as a file of it changes.
here=$(dirname "$(realpath "$0")")
if [ "$1" = --inside ]; then
	shift
	export HYPR_DEV=headless
	exec Hyprland --config "${HYPR_DEV_CONFIG:-$here/../hypr/hyprland.lua}" "$@"
fi
session=$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/hypr-headless.XXXXXX")
trap 'rm -f "$session"' EXIT
printf '#!/bin/sh\nexec %s --inside' "$(realpath "$0")" > "$session"
for a in "$@"; do printf " '%s'" "$(printf %s "$a" | sed "s/'/'\\\\''/g")" >> "$session"; done
chmod +x "$session"
systemd-run --user --scope --quiet -p MemoryMax=4G -p MemorySwapMax=0 \
	env -u WAYLAND_DISPLAY -u DISPLAY dbus-run-session -- \
	kwin_wayland --virtual --no-lockscreen --width 1920 --height 1200 \
	--socket "hypr-headless-$$" --exit-with-session "$session"
