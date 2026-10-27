#!/bin/bash
# Headless test of the nalthis style: runs an app inside an invisible KWin with
# its own D-Bus and a copy of the config, screenshots it, and exits. Nothing on
# the machine or the live session changes.
#
#   dev/test.sh <out.png> [--knobs "hue tint depth accent"] [--then "..."] <app> [args...]
#
# --then switches the color scheme while the app runs (like System Settings)
# and takes a second screenshot, <out>-then.png: checks live recolor.
# Work files go to $NALTHIS_DEV (default $XDG_RUNTIME_DIR/nalthis-dev).
set -euo pipefail
dev=$(cd "$(dirname "$0")" && pwd)
module=$(dirname "$dev")
work=${NALTHIS_DEV:-$XDG_RUNTIME_DIR/nalthis-dev}
out=$(realpath -m "$1"); shift
knobs="255 1 0 250" then=""
while [[ $1 == --* ]]; do
    case $1 in
        --knobs) knobs=$2 ;;
        --then) then=$2 ;;
    esac
    shift 2
done

# A small root: our style where it will be installed, Breeze where it is,
# so the style's relative @import resolves as on the real machine.
rm -rf "$work"
mkdir -p "$work/root/usr/local/share/union/styles" "$work/root/usr/share" "$work/data/color-schemes" "$work/config"
cp -r "$module/system/usr/local/share/union/styles/nalthis" "$work/root/usr/local/share/union/styles/"
ln -s /usr/share/union "$work/root/usr/share/union"
(cd "$module/pkg" && go build -o "$work-bin/nalthis" .)
"$work-bin/nalthis" colors Nalthis $knobs > "$work/data/color-schemes/Nalthis.colors"
[[ -n $then ]] && "$work-bin/nalthis" colors NalthisThen $then > "$work/data/color-schemes/NalthisThen.colors"
"$work-bin/nalthis" merge "$HOME/.config/kdeglobals" "$work/data/color-schemes/Nalthis.colors" \
    | sed '/^\[KDE\]$/a widgetStyle=Union\nunionStyle=nalthis' > "$work/config/kdeglobals"
grep -q '^\[KDE\]$' "$work/config/kdeglobals" || printf '[KDE]\nwidgetStyle=Union\nunionStyle=nalthis\n' >> "$work/config/kdeglobals"

inner="$work/inner.sh"
{
    echo '#!/bin/bash'
    printf 'export XDG_CONFIG_HOME=%q XDG_DATA_DIRS=%q QT_QPA_PLATFORM=wayland KDE_DEBUG=1\n' \
        "$work/config" "$work/root/usr/local/share:$work/data:/usr/local/share:/usr/share"
    printf '%q ' "$@"; printf '>%q 2>&1 &\n' "$out.log"
    echo 'sleep 6'
    printf 'spectacle -b -n -f -o %q\n' "$out"
    if [[ -n $then ]]; then
        printf 'plasma-apply-colorscheme NalthisThen >>%q 2>&1\n' "$out.log"
        echo 'sleep 3'
        printf 'spectacle -b -n -f -o %q\n' "${out%.png}-then.png"
    fi
    echo 'sleep 1; kill %1 2>/dev/null'
} > "$inner"
chmod +x "$inner"
dbus-run-session -- kwin_wayland --virtual --width 1280 --height 800 --no-lockscreen \
    --socket "wl-nalthis-$$" --exit-with-session "$inner" > "$work/kwin.log" 2>&1
echo "$out"
