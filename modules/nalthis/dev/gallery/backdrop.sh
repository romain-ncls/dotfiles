#!/bin/bash
# Runs an app over a light backdrop window (see backdrop.qml).
here=$(cd "$(dirname "$0")" && pwd)
/usr/lib/qt6/bin/qml "$here/backdrop.qml" &
sleep 1.5
"$@"
