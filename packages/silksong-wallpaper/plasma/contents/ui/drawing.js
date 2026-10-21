/*
 * The screens of one process (the lock screen's, or plasmashell's) make their worlds only once
 * every one of them shows its drawing (Drawing.qml): a world is made on the GUI thread, all at
 * once, and would hold back the first frame of the screens not drawn yet. Then their drawings fade
 * away together, once every world has drawn its first frame. One that never draws (its screen
 * off) holds the others back only so long (Drawing.qml).
 */
.pragma library

let drawings = [];

function join(drawing) {
    drawings.push(drawing);
}

function leave(drawing) {
    drawings = drawings.filter(d => d !== drawing);
    shown();
    framed();
}

// Asked by a drawing once it's on screen: when every one is, all may have their worlds made.
function shown() {
    if (drawings.every(d => d.drawn || d.up)) {
        drawings.forEach(d => {
            d.up = true;
        });
    }
}

// Asked by a drawing once the world under it has drawn its first frame: when every one has, all
// fade away.
function framed() {
    if (drawings.every(d => d.framed || d.leaving)) {
        drawings.forEach(d => {
            d.leaving = true;
        });
    }
}
