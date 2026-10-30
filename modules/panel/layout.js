// The bottom panel, rebuilt from scratch (plasmashell's scripting API:
// https://develop.kde.org/docs/plasma/scripting/). Widget options are the
// keys of their config groups, as the layout file stores them.

for (const old of panels()) {
    if (old.location === "bottom") {
        old.remove();
    }
}

const panel = new Panel();
panel.location = "bottom";
panel.height = 46;
panel.floating = false; // docked (nalthis)
panel.opacity = "translucent"; // always the glass, even with a maximized window

function add(plugin, config) {
    const widget = panel.addWidget(plugin);
    for (const [group, keys] of Object.entries(config || {})) {
        widget.currentConfigGroup = group.split("/");
        for (const [key, value] of Object.entries(keys)) {
            widget.writeConfig(key, value);
        }
    }
    widget.currentConfigGroup = [];
    return widget;
}

// Left
add("org.kde.plasma.pager", {
    General: {
        displayedText: 2, // no text: the current desktop is the accent cell
        showWindowOutlines: false,
    },
});
add("org.kde.plasma.claudeusage", { General: { showIcon: false } });

// Middle: two flexible spacers center what is between them on the panel.
add("org.kde.plasma.panelspacer");
add("org.kde.plasma.kickoff", { General: { compactMode: true } }); // tighter rows
add("org.kde.plasma.icontasks", {
    General: { launchers: "applications:systemsettings.desktop,preferred://filemanager,preferred://browser" },
});
add("org.kde.plasma.panelspacer");

// Right
add("org.kde.plasma.systemtray", { General: { hiddenItems: "Easy Effects" } });
add("org.kde.plasma.digitalclock", {
    Appearance: {
        autoFontAndSize: false, // (it fills the panel's height)
        fontSize: 10,
        fontWeight: 400,
    },
});
add("nalthis.peek");
