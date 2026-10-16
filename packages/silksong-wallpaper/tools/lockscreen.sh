#!/usr/bin/env bash
# The Silksong lock screen prompt (../lockscreen), for this user only.
#
# Plasma's lock screen draws its prompt from a shell package's lockscreen/LockScreen.qml: the
# package plasmashellrc names, or else $PLASMA_DEFAULT_SHELL, or else org.kde.plasma.desktop.
# Nothing in the system is changed, and the desktop is left alone:
#
# - ~/.local/share/plasma/shells/com.github.romain-ncls.silksong-lock is a shell package that
#   holds only lockscreen/; for everything else Plasma falls back to org.kde.plasma.desktop.
#   LockScreen.qml is copied (Plasma refuses an entry file whose real path is outside its
#   package); the rest are links, to our files and to the system's own prompt files.
# - a drop-in gives KWin, which starts the lock screen, PLASMA_DEFAULT_SHELL naming it. Only
#   KWin: plasmashell would take it for its own shell and lay out a new, empty desktop.
#
#   lockscreen.sh install     make both (KWin reads the drop-in when it next starts: next login)
#   lockscreen.sh link        make the package again, against the system's current shell
#   lockscreen.sh uninstall   remove both: Plasma's own prompt again from the next login
#
# install also links the package again at each login (a Plasma env script), which follows
# Plasma updates, NixOS or Arch alike. The prompt needs the game's art (tools/extract_ui.py);
# without it, LockScreen.qml shows Plasma's own prompt.
set -euo pipefail

here=$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)
data=${XDG_DATA_HOME:-$HOME/.local/share}
config=${XDG_CONFIG_HOME:-$HOME/.config}
id=com.github.romain-ncls.silksong-lock
package=$data/plasma/shells/$id
dropin=$config/systemd/user/plasma-kwin_wayland.service.d/silksong-lock.conf
hook=$config/plasma-workspace/env/silksong-lock.sh

# The system's desktop shell: NixOS's profile first (a path that follows each rebuild), then the
# data dirs (but not single store paths, which a rebuild leaves behind), then the usual places.
system_shell() {
    local dirs d
    IFS=: read -r -a dirs <<< "/run/current-system/sw/share:${XDG_DATA_DIRS:-}:/usr/local/share:/usr/share"
    for d in "${dirs[@]}"; do
        [[ -n $d && $d != /nix/store/* && $d != "$data" ]] || continue
        if [[ -f $d/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/LockScreen.qml ]]; then
            echo "$d/plasma/shells/org.kde.plasma.desktop"
            return
        fi
    done
    echo "lockscreen.sh: no org.kde.plasma.desktop shell in the system" >&2
    return 1
}

link() {
    local src tmp lock entry name
    src=$(system_shell)
    [[ $package == */plasma/shells/$id ]] || exit 1
    tmp=$package.new
    rm -rf -- "$tmp"
    lock=$tmp/contents/lockscreen
    mkdir -p "$lock"
    cat > "$tmp/metadata.json" <<EOF
{
    "KPackageStructure": "Plasma/Shell",
    "KPlugin": {
        "Id": "$id",
        "Name": "Silksong lock screen",
        "Description": "Plasma's desktop shell with the Silksong lock screen prompt ($here/lockscreen)"
    },
    "X-Plasma-APIVersion": "2",
    "X-Plasma-FallbackPackage": "org.kde.plasma.desktop"
}
EOF
    # Plasma's own prompt files, for LockScreenUi.qml (the fallback) and what both prompts load;
    # not its settings (config.*), which the fallback package gives as they are.
    for entry in "$src"/contents/lockscreen/*; do
        name=${entry##*/}
        [[ $name == LockScreen.qml || $name == config.* ]] || ln -s "$entry" "$lock/$name"
    done
    for entry in "$here"/lockscreen/*.qml; do
        name=${entry##*/}
        [[ $name == LockScreen.qml ]] || ln -sfn "$entry" "$lock/$name"
    done
    cp -- "$here/lockscreen/LockScreen.qml" "$lock/LockScreen.qml"
    rm -rf -- "$package.old"
    if [[ -e $package ]]; then
        mv -- "$package" "$package.old"
    fi
    mv -- "$tmp" "$package"
    rm -rf -- "$package.old"
}

case ${1:-} in
    link)
        link
        ;;
    install)
        link
        mkdir -p "${dropin%/*}" "${hook%/*}"
        printf '%s\n' "# The Silksong lock screen prompt for KWin's lock screen only ($here/tools/lockscreen.sh)." \
            "[Service]" "Environment=PLASMA_DEFAULT_SHELL=$id" > "$dropin"
        printf '%s\n' "# Links the Silksong lock screen package against this login's Plasma ($here/tools/lockscreen.sh)." \
            "\"$here/tools/lockscreen.sh\" link >/dev/null 2>&1 || true" > "$hook"
        systemctl --user daemon-reload
        echo "Installed: the Silksong prompt from the next login (Plasma's own while the game's art is missing)."
        ;;
    uninstall)
        rm -f -- "$dropin" "$hook"
        [[ $package == */plasma/shells/$id ]] && rm -rf -- "$package"
        systemctl --user daemon-reload
        echo "Removed: Plasma's own prompt from the next login."
        ;;
    *)
        sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
        exit 2
        ;;
esac
