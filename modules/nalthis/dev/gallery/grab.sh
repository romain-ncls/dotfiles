#!/bin/bash
# Renders the QtWidgets gallery offscreen with the nalthis style and colors set
# up by the last dev/test.sh run: window.png, menu.png, combo.png in <dir>.
set -euo pipefail
work=${NALTHIS_DEV:-$XDG_RUNTIME_DIR/nalthis-dev}
out=$(realpath -m "$1")
mkdir -p "$out"
XDG_CONFIG_HOME="$work/config" XDG_DATA_DIRS="$work/data:/usr/local/share:/usr/share" \
QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME=kde KDE_DEBUG=1 GALLERY_GRAB="$out" \
    systemd-run --user --scope -q -p MemoryMax=1G -p MemorySwapMax=0 timeout 30 "$work-bin/widgets-gallery"
ls "$out"
