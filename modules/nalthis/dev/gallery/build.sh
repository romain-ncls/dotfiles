#!/bin/bash
# Builds the QtWidgets gallery into $NALTHIS_DEV/bin (not in the repo).
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
bin=${NALTHIS_DEV:-$XDG_RUNTIME_DIR/nalthis-dev}-bin
mkdir -p "$bin"
g++ -O1 -fPIC -std=c++17 "$here/widgets.cpp" -o "$bin/widgets-gallery" $(pkg-config --cflags --libs Qt6Widgets)
echo "$bin/widgets-gallery"
