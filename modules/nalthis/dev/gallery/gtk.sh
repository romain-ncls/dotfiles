#!/bin/bash
# Builds the GTK 3 and libadwaita galleries into $NALTHIS_DEV-bin (not in the
# repo); run them through dev/test.sh --gtk.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${NALTHIS_DEV:-$XDG_RUNTIME_DIR/nalthis-dev}-bin
mkdir -p "$bin"
gcc -O1 "$here/gtk3.c" -o "$bin/gtk3-gallery" $(pkg-config --cflags --libs gtk+-3.0)
gcc -O1 "$here/adw.c" -o "$bin/adw-gallery" $(pkg-config --cflags --libs libadwaita-1)
echo "$bin/gtk3-gallery $bin/adw-gallery"
