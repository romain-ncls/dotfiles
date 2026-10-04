// Loaded into KWin by the logi-wheel daemon: reports each activated window.
function report(w) {
    if (!w) return;
    callDBus("local.LogiWheel", "/local/LogiWheel", "local.LogiWheel", "ActiveWindow",
             String(w.resourceClass || ""), String(w.desktopFileName || ""));
}
workspace.windowActivated.connect(report);
report(workspace.activeWindow);
