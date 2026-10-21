/*
 * The lock screen's screens (one LockScreen.qml each, in one process) make their prompts only
 * once every one of them has drawn its first frame: the first prompt made compiles it all on the
 * GUI thread (a tenth of a second), which would hold back the first frame of the screens not drawn
 * yet. One that never draws (its screen off) makes its own half a second on (LockScreen.qml).
 */
.pragma library

let screens = [];

function join(screen) {
    screens.push(screen);
}

function leave(screen) {
    screens = screens.filter(s => s !== screen);
    shown();
}

// Asked by a screen once it has drawn its first frame: when every one has, all make their prompts.
function shown() {
    if (screens.every(s => s.drawn)) {
        screens.forEach(s => s.makePrompt());
    }
}
