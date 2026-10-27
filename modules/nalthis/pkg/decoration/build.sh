#!/bin/bash
# Builds the window decoration with Qt's moc and g++ (no CMake), like the
# settings page.
#   build.sh <out-dir>   writes <out-dir>/org.kde.kdecoration3/org.kde.nalthis.so
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
build="$out/.build-decoration"
mkdir -p "$build" "$out/org.kde.kdecoration3"
incs=(-I"$here" -I/usr/include/KDecoration3 -I/usr/include/KF6/KColorScheme -I/usr/include/KF6/KConfig -I/usr/include/KF6/KConfigCore -I/usr/include/KF6/KConfigGui)
# moc expands KDE's plugin macro, so it needs the same headers as the compiler.
# shellcheck disable=SC2046
/usr/lib/qt6/moc "${incs[@]}" $(pkg-config --cflags-only-I Qt6Gui KF6CoreAddons) "$here/nalthis-decoration.cpp" -o "$build/nalthis-decoration.moc"
# shellcheck disable=SC2046
g++ -O2 -fPIC -shared -std=c++20 -DQT_NO_DEBUG -DQT_NO_CAST_FROM_ASCII \
    -I"$build" "${incs[@]}" "$here/nalthis-decoration.cpp" \
    $(pkg-config --cflags --libs Qt6Gui KF6CoreAddons) -lkdecorations3 -lKF6ColorScheme -lKF6ConfigCore \
    -o "$out/org.kde.kdecoration3/org.kde.nalthis.so"
echo "$out/org.kde.kdecoration3/org.kde.nalthis.so"
