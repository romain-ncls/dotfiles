#!/bin/bash
# Headless test of the nalthis style: runs an app inside an invisible KWin with
# its own D-Bus and a copy of the config, screenshots it, and exits. Nothing on
# the machine or the live session changes.
#
#   dev/test.sh <out.png> [--knobs "hue tint depth accent"] [--then "..."]
#       [--decoration] [--plasma] [--icons themes-dir] [--gtk] [--wait seconds] <app> [args...]
#
# --then applies other knobs while the app runs, with `nalthis apply` (as the
# sliders do), and takes a second screenshot, <out>-then.png: checks live recolor.
# Hover: run the app on X11 (QT_QPA_PLATFORM=xcb) and move the pointer with
# xdotool, after kwriteconfig6 --file kwinrc --group Xwayland --key
# XwaylandEisNoPrompt true and a KWin reconfigure (else KWin asks first).
# Work files go to $NALTHIS_DEV (default $XDG_RUNTIME_DIR/nalthis-dev).
set -euo pipefail
dev=$(cd "$(dirname "$0")" && pwd)
module=$(dirname "$dev")
work=${NALTHIS_DEV:-$XDG_RUNTIME_DIR/nalthis-dev}
out=$(realpath -m "$1"); shift
knobs="255 1 0 250" then="" decoration="" plasma="" icons="" gtk="" wait=6
while [[ $1 == --* ]]; do
    case $1 in
        --knobs) knobs=$2; shift ;;
        --then) then=$2; shift ;;
        --decoration) decoration=1 ;; # KWin uses our decoration (built by pkg/decoration/build.sh)
        --plasma) plasma=1 ;; # our Plasma style (run plasmashell as the app)
        --wait) wait=$2; shift ;; # seconds before the screenshot
        --gtk) gtk=1 ;; # GTK: a copy of ~/.config/gtk-3.0 and gtk-4.0 with our nalthis.css
        --icons) icons=$2; shift ;; # a folder of icon themes holding nalthis (built with nalthis icon-theme)
    esac
    shift
done

rm -rf "$work"
mkdir -p "$work/data/color-schemes" "$work/config"
(cd "$module/pkg" && go build -o "$work-bin/nalthis" .)
"$work-bin/nalthis" colors Nalthis $knobs > "$work/data/color-schemes/Nalthis.colors"
"$work-bin/nalthis" konsole "$work/data/konsole" $knobs # and a profile using it, for konsole --profile Nalthis
printf "[Appearance]\nColorScheme=Nalthis\nFont=Fira Code Retina,11,-1,5,53,0,0,0,0,0,Regular\n[General]\nName=Nalthis\nParent=FALLBACK/\nTerminalMargin=8\n" > "$work/data/konsole/Nalthis.profile"
"$work-bin/nalthis" merge "$HOME/.config/kdeglobals" "$work/data/color-schemes/Nalthis.colors" > "$work/config/kdeglobals"
kwriteconfig6 --file "$work/config/kdeglobals" --group KDE --key widgetStyle Darkly
# Darkly's settings as module.yaml declares them (its darklyrc: block).
awk '/^  darklyrc:/ { on = 1; next } on && /^  [^ ]/ { on = 0 }
     on && /^    [^ ]/ { group = $1; sub(/:$/, "", group) }
     on && /^      [^ #]/ { key = $1; sub(/:$/, "", key); print group, key, $2 }' "$module/module.yaml" |
    while read -r group key value; do
        kwriteconfig6 --file "$work/config/darklyrc" --group "$group" --key "$key" "$value"
    done
if [[ -n $gtk ]]; then
    cp -r "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" "$HOME/.config/dconf" "$work/config/" # dconf: GTK 3 on Wayland takes its theme from GSettings
    "$work-bin/nalthis" gtk "$work/config" $knobs
fi
if [[ -n $icons ]]; then
    ln -s "$(realpath "$icons")" "$work/data/icons"
    kwriteconfig6 --file "$work/config/kdeglobals" --group Icons --key Theme nalthis
fi
if [[ -n $plasma ]]; then
    "$work-bin/nalthis" plasma-theme "$work/data/plasma/desktoptheme/nalthis"
    kwriteconfig6 --file "$work/config/plasmarc" --group Theme --key name nalthis
    # Docked, always glass: as on wandersail (hosts/wandersail/host.yaml).
    kwriteconfig6 --file "$work/config/plasmashellrc" --group PlasmaViews --group "Panel 2" --key floating 0
    kwriteconfig6 --file "$work/config/plasmashellrc" --group PlasmaViews --group "Panel 2" --key panelOpacity 2
fi
kwin_env=()
if [[ -n $decoration ]]; then
    "$module/pkg/decoration/build.sh" "$work-bin/plugins" > /dev/null
    cp "$HOME/.config/kwinrc" "$HOME/.config/breezerc" "$work/config/" # breezerc: the window exceptions
    kwriteconfig6 --file "$work/config/kwinrc" --group org.kde.kdecoration2 --key library org.kde.nalthis
    kwin_env=(env XDG_CONFIG_HOME="$work/config" QT_PLUGIN_PATH="$work-bin/plugins")
fi

inner="$work/inner.sh"
{
    echo '#!/bin/bash'
    printf 'export XDG_CONFIG_HOME=%q XDG_DATA_HOME=%q XDG_DATA_DIRS=%q QT_QPA_PLATFORM=wayland KDE_DEBUG=1\n' \
        "$work/config" "$work/datahome" "$work/data:/usr/local/share:/usr/share"
    printf '%q ' "$@"; printf '>%q 2>&1 &\n' "$out.log"
    echo "sleep $wait"
    printf 'spectacle -b -n -f -o %q\n' "$out"
    if [[ -n $then ]]; then
        printf '%q apply %s >>%q 2>&1\n' "$work-bin/nalthis" "$then" "$out.log"
        echo 'sleep 3'
        printf 'spectacle -b -n -f -o %q\n' "${out%.png}-then.png"
    fi
    echo 'sleep 1; kill %1 2>/dev/null; wait'
} > "$inner"
chmod +x "$inner"
# Capped (memory-heavy: a whole KWin plus the app); one run at a time.
systemd-run --user --scope -q -p MemoryMax=3G -p MemorySwapMax=0 nice -n 10 \
    timeout ${NALTHIS_TIMEOUT:-60} dbus-run-session -- "${kwin_env[@]}" kwin_wayland --virtual --xwayland --width 1280 --height 800 --no-lockscreen \
        --socket "wl-nalthis-$$" --exit-with-session "$inner" > "$work/kwin.log" 2>&1
echo "$out"
