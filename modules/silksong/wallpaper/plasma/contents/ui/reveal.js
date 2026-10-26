/*
 * The screens of one process (the lock screen's, or plasmashell's) fade in together, once every
 * one of them has everything it shows. They share one image thread, which serves what was asked
 * for last first: each on its own, they would show one after the other, the one made last first.
 *
 * Each scene joins as it's made and leaves as it goes; one that has shown already doesn't hold
 * the others back when they load again.
 */
.pragma library

let scenes = [];

function join(scene) {
    scenes.push(scene);
}

// One that goes no longer holds the others back: those that were only waiting for it are revealed.
function leave(scene) {
    scenes = scenes.filter(s => s !== scene);
    settled();
}

// Asked by a scene that has everything it shows: once every other one has too, all are revealed.
function settled() {
    if (scenes.every(s => s.revealed || s.settled)) {
        scenes.forEach(s => {
            s.revealed = true;
        });
    }
}
