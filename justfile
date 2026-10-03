# Machine configuration for MENADION (home) and the work PC.
# `just` lists the recipes. System recipes call sudo: run them in a real terminal.

sys := "aconfmgr --config " + justfile_directory() + "/system"
role := `chezmoi execute-template '{{ .role }}' 2>/dev/null || echo unknown`

default:
    @just --list

# Make the whole machine match the repo: system first, then $HOME
apply: apply-system apply-home

# Packages, /etc, /boot and services (aconfmgr, uses sudo)
apply-system:
    {{sys}} apply

# Dotfiles, KDE settings, per-user setup (chezmoi; Bitwarden unlocks only if a template needs it)
apply-home:
    chezmoi apply

# What `just apply` would change
diff:
    -{{sys}} diff
    chezmoi diff

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
    echo "== home (chezmoi status)"
    out=$(chezmoi status --exclude scripts)
    if [[ -n $out ]]; then echo "$out"; status=1; else echo "clean"; fi
    echo "== KDE keys"
    scripts/kde-config check {{role}} && echo "clean" || status=1
    exit $status

# Pull a changed $HOME file back into the repo, e.g. `just add ~/.config/fish/config.fish`
add +files:
    chezmoi add {{files}}
