#!/bin/bash
# Builds the System Settings page with Qt's own tools (moc, rcc, g++): no
# CMake needed. The QML goes into a resource at /kcm/kcm_nalthis, as KDE's
# kcmutils_add_qml_kcm does.
#   build.sh <out-dir>   writes <out-dir>/plasma/kcms/systemsettings/kcm_nalthis.so
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=$(realpath -m "$1")
build="$out/.build"
mkdir -p "$build" "$out/plasma/kcms/systemsettings"
qt=/usr/lib/qt6

incs=(-I"$here" -I/usr/include/KF6/KCMUtilsQuick -I/usr/include/KF6/KCMUtilsCore -I/usr/include/KF6/KCMUtils)
# moc expands KDE's plugin macro, so it needs the same headers as the compiler.
# shellcheck disable=SC2046
"$qt/moc" "${incs[@]}" $(pkg-config --cflags-only-I Qt6Quick Qt6Qml KF6CoreAddons) "$here/kcm_nalthis.cpp" -o "$build/kcm_nalthis.moc"
cat > "$build/kcm_nalthis.qrc" <<EOF
<RCC><qresource prefix="/kcm/kcm_nalthis"><file alias="main.qml">$here/ui/main.qml</file></qresource></RCC>
EOF
"$qt/rcc" --name kcm_nalthis "$build/kcm_nalthis.qrc" -o "$build/qrc.cpp"

# shellcheck disable=SC2046
g++ -O2 -fPIC -shared -std=c++17 -DQT_NO_DEBUG -DQT_NO_CAST_FROM_ASCII -DTRANSLATION_DOMAIN='"kcm_nalthis"' \
    -I"$build" "${incs[@]}" \
    "$here/kcm_nalthis.cpp" "$build/qrc.cpp" \
    $(pkg-config --cflags --libs Qt6Quick Qt6Qml KF6CoreAddons) -lKF6KCMUtilsQuick -lKF6KCMUtilsCore \
    -o "$out/plasma/kcms/systemsettings/kcm_nalthis.so"
echo "$out/plasma/kcms/systemsettings/kcm_nalthis.so"
