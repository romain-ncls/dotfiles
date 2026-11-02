// Popups of the panel's middle widgets (the launcher) open centered on their
// screen, as Windows' Start menu; the others stay over their widget. Plasma
// anchors every applet popup to its widget, with no option, and gives them
// no name: the rule goes by where the popup opens.
function centre(w) {
    if (!w.appletPopup) {
        return;
    }
    const area = workspace.clientArea(KWin.ScreenArea, w.output, workspace.currentDesktop);
    const g = w.frameGeometry;
    const mid = g.x + g.width / 2;
    if (mid < area.x + area.width / 3 || mid > area.x + 2 * area.width / 3) {
        return;
    }
    const x = Math.round(area.x + (area.width - g.width) / 2);
    if (g.x !== x) {
        w.frameGeometry = { x: x, y: g.y, width: g.width, height: g.height };
    }
}

workspace.windowAdded.connect(centre);
