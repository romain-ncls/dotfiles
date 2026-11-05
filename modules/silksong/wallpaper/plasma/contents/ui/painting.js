/*
 * The screens of one process (the lock screen's, or plasmashell's) make their worlds only once
 * every one of them shows its painting (Painting.qml): a world is made on the GUI thread, all at
 * once, and would hold back the first frame of the screens not shown yet. Then the paintings end
 * together, once every world has drawn its first frame, as fast as the one least far along may.
 * One that never shows (its screen off) holds the others back only so long (Painting.qml).
 */
.pragma library

let paintings = [];

function join(painting) {
    paintings.push(painting);
}

function leave(painting) {
    paintings = paintings.filter(p => p !== painting);
    shown();
    framed();
}

// Asked by a painting once it's on screen: when every one is, all may have their worlds made.
function shown() {
    if (paintings.every(p => p.shown || p.allShown)) {
        paintings.forEach(p => {
            p.allShown = true;
        });
    }
}

// Asked by a painting once the world under it has drawn its first frame: when every one has, all
// end, for as long as the one least far along needs.
function framed() {
    if (paintings.every(p => p.framed || p.leaving)) {
        const waiting = paintings.filter(p => !p.leaving && p.shown);
        const finish = Math.max(0, ...waiting.map(p => p.finishNow()));
        paintings.forEach(p => p.leave(finish || p.finishNow()));
    }
}
