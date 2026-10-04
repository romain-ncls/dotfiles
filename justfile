# Machine configuration for MENADION (home) and the work PC.
# `just` lists the recipes. System recipes call sudo: run them in a real terminal.

sys := "aconfmgr --config " + justfile_directory() + "/system"
role := `chezmoi execute-template '{{ .role }}' 2>/dev/null || echo unknown`

default:
    @just --list

# Make the whole machine match the repo: system first, then $HOME
apply: apply-system apply-home

# Packages, /etc, services (aconfmgr), then the hand-written part of limine.conf (uses sudo)
apply-system:
    {{sys}} apply
    if [ -f system/limine/{{role}}.conf ]; then sudo scripts/limine-conf apply system/limine/{{role}}.conf; fi

# Dotfiles, KDE settings, per-user setup (chezmoi; Bitwarden unlocks only if a template needs it)
apply-home:
    chezmoi apply

# What `just apply` would change
diff:
    #!/usr/bin/env bash
    set -uo pipefail
    want=$(scripts/aconf-packages)
    echo "== packages to install"
    comm -23 <(echo "$want") <(pacman -Qq | sort) | sed 's/^/+ /'
    echo "== packages to remove (installed explicitly, not in system/)"
    comm -13 <(echo "$want") <(pacman -Qqe | sort) | sed 's/^/- /'
    echo "== system files"
    {{sys}} diff / || true
    if [[ -f system/limine/{{role}}.conf ]]; then
        echo "== limine.conf"
        sudo scripts/limine-conf diff system/limine/{{role}}.conf || true
    fi
    echo "== home"
    chezmoi diff --exclude scripts

# Everything on the machine that the repo does not know about.
# Clean means: no new system/99-unsorted.sh, no chezmoi changes, KDE keys in sync.
drift:
    #!/usr/bin/env bash
    set -uo pipefail
    status=0
    echo "== system (aconfmgr save)"
    {{sys}} save
    if [[ -s system/99-unsorted.sh ]]; then
        echo "-> system/99-unsorted.sh lists unrecorded system changes: sort them into system/*.sh"
        status=1
    else
        echo "clean"
    fi
    if [[ -f system/limine/{{role}}.conf ]]; then
        echo "== limine.conf"
        sudo scripts/limine-conf diff system/limine/{{role}}.conf || status=1
    fi
    echo "== home (chezmoi status)"
    out=$(chezmoi status --exclude scripts)
    if [[ -n $out ]]; then echo "$out"; status=1; else echo "clean"; fi
    echo "== KDE keys"
    scripts/kde-config check {{role}} && echo "clean" || status=1
    echo "== mpv (read in place from mpv/, so changes show up in git, not chezmoi)"
    out=$(git status --short -- mpv)
    if [[ -n $out ]]; then echo "$out"; echo "-> commit them (and git pull on the other OS)"; status=1; else echo "clean"; fi
    exit $status

# Pull a changed $HOME file back into the repo, e.g. `just add ~/.config/fish/config.fish`
add +files:
    chezmoi add {{files}}
