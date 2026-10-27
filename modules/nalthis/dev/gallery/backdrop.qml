// A light window filling the headless screen, behind the app under test, so
// window shadows show (the headless desktop is black). Run by backdrop.sh.
import QtQuick
import QtQuick.Window

Window {
    visible: true
    x: 0; y: 0
    width: 1280; height: 800
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnBottomHint
    color: "#c9ced6"
}
