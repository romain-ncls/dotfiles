/*
 * The screens of one process (the lock screen's, or plasmashell's) make their worlds only once
 * every one of them shows its painting (Painting.qml): a world is made on the GUI thread, all at
 * once, and would hold back the first frame of the screens not shown yet. Then the paintings end
 * together, once every world has everything it shows and every brush is all but done.
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

// Asked by a painting once the world may show under it: when every one's may, all end together.
function framed() {
    if (paintings.every(p => p.framed || p.leaving)) {
        paintings.forEach(p => p.leave());
    }
}
