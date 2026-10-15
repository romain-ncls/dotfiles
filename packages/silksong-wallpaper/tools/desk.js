/*
 * This desk, as Qt.application.screens reports it to the wallpaper, for the tools that stand in
 * for Plasma (preview.qml, bench.qml) and for the views tools/derive.qml makes for its screens:
 * where each screen sits, its size in pixels and its density, which Qt works out from the size in
 * whole millimetres KWin gives it (its EDID's), as the mean of its two axes'.
 */
.pragma library

function screen(name, virtualX, width, height, widthMm, heightMm) {
    // QScreen::physicalDotsPerInch() / 25.4, worked out as Qt does.
    return { name: name, virtualX: virtualX, width: width, height: height,
             pixelDensity: (height / heightMm + width / widthMm) * 12.7 / 25.4 };
}

const screens = [
    screen("DP-3", 0, 1920, 1080, 476, 268),
    screen("eDP-1", 1920, 1920, 1200, 344, 215),
    screen("HDMI-A-1", 3840, 1920, 1080, 476, 268),
];

const gapMm = 15; // GapMm, as by default
