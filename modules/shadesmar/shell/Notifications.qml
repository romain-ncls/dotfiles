// Notifications, where Plasma has them: popups in the bottom right corner of
// the bar's screen, above the bar, the newest at the bottom; then the
// history, under the bar's bell (NotificationCenter.qml).
//
// Each is kept as a copy (an entry): what the app said, its icon, when, the
// file it's about. An app may withdraw its notification (Discord does as its
// next message comes, Teams as its popup goes): its object goes, and with it
// the app's own buttons, but not the copy, on screen for its time, then in
// the history, where a click shows the app's window instead. The history
// lasts across the shell's restarts (a file in its state folder, under the
// home folder only its owner reads): the last 100 of the last day, without
// what an app marked transient, without pictures. The apps in `brief` (a
// screenshot taken) are only on screen, as transient ones.
//
// An app's popups stack, its newest in front (NotificationStack.qml); the
// same notification again counts ("×2") instead. Their time (5 s when the
// app leaves it to us, or asks for none: Discord's would stay until
// clicked; critical ones stay; new words start it again) pauses while the
// pointer is on them. A click runs the notification's default
// action (Discord: its channel), else opens its file, else shows its app; a
// right click dismisses it, gone from the history too. Do not disturb: no
// popups but critical ones. A notification about a file (Plasma's x-kde-urls
// hint: LumineCapture's screenshots) shows it as a picture, with Open and
// Show in Files; one in the runtime dir is a temporary copy (a shot only
// copied): its picture only.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland

Scope {
    id: notifications

    property var screen
    property bool dnd: false
    onDndChanged: save()

    // the copies, the newest first
    property var entries: []
    readonly property var byKey: {
        const m = {}
        for (const e of entries)
            m[e.key] = e
        return m
    }
    // the apps' own objects, by key, while they keep them
    property var live: ({})
    // when the bell was last opened
    property real seenAt: 0

    readonly property var history: entries.filter(e => !e.popup)
    readonly property int unread: history.filter(e => e.time > seenAt).length
    // by app: the bell's list, all of them (the app with the newest
    // first); the popups' stacks (the newest app's at the bottom)
    readonly property var listedBy: by(entries)
    readonly property var groups: order(entries).map(g => ({ key: g }))
    readonly property var popupsBy: by(entries.filter(e => e.popup))
    readonly property var stacks: order(entries.filter(e => e.popup)).reverse().map(g => ({ key: g }))

    // apps whose notifications aren't kept (their app names)
    readonly property var brief: ["LumineCapture"]
    readonly property int keep: 100
    readonly property real keepFor: 24 * 3600 * 1000
    property int serial: 0

    function by(list) {
        const m = {}
        for (const e of list) {
            if (!m[e.group])
                m[e.group] = []
            m[e.group].push(e)
        }
        return m
    }
    function order(list) {
        const seen = []
        for (const e of list)
            if (!seen.includes(e.group))
                seen.push(e.group)
        return seen
    }

    function critical(n) {
        return n.urgency === NotificationUrgency.Critical
    }

    // An image that's a theme icon's name (image://icon/…) is an icon, given
    // a fallback when the theme lacks it.
    function picture(n) {
        return n.image.startsWith("image://icon/") ? "" : n.image
    }
    function icon(n) {
        const entry = n.desktopEntry ? DesktopEntries.byId(n.desktopEntry) : null
        const name = n.image.startsWith("image://icon/") ? n.image.slice(13) : n.appIcon || (entry ? entry.icon : "")
        if (name.startsWith("/") || name.startsWith("file:"))
            return name
        return Quickshell.iconPath(name, "dialog-information")
    }

    // The files it's about, as file:// URLs (x-kde-urls: a list, or one).
    function files(n) {
        const urls = n.hints["x-kde-urls"]
        const list = typeof urls === "string" ? [urls] : urls ? Array.from(urls) : []
        return list.filter(u => typeof u === "string" && u.startsWith("file://"))
    }
    // not a temporary copy in the runtime dir
    function kept(url) {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR")
        return !runtime || !decodeURIComponent(url.slice(7)).startsWith(runtime + "/")
    }

    // What an entry copies of the app's notification. Unnamed senders
    // (notify-send's) don't stack: their group is their key.
    function copy(n) {
        const named = n.appName !== "" && n.appName !== "notify-send"
        return {
            id: n.id,
            app: n.appName,
            entry: n.desktopEntry,
            icon: icon(n),
            picture: picture(n),
            summary: n.summary,
            body: n.body,
            critical: critical(n),
            resident: n.resident,
            transient: n.transient || brief.includes(n.appName),
            timeout: critical(n) ? 0 : n.expireTimeout > 0 ? n.expireTimeout : 5000,
            files: files(n),
            group: named ? (n.desktopEntry || n.appName).toLowerCase() : ""
        }
    }

    function arrive(n, quiet) {
        const now = Date.now()
        const e = copy(n)
        const shown = !quiet && (!dnd || e.critical)
        if (!shown && e.transient) {
            n.expire()
            return
        }
        // the same again: that one, counted, and the newest
        const same = entries.find(o => o.app === e.app && o.entry === e.entry && o.summary === e.summary && o.body === e.body && String(o.files) === String(e.files))
        e.key = same ? same.key : `${now.toString(36)}-${++serial}`
        e.group = same ? same.group : e.group || e.key
        e.count = same ? same.count + 1 : 1
        e.time = now
        e.popup = shown
        e.until = shown && e.timeout > 0 ? now + e.timeout : 0
        const old = same ? live[same.key] : null
        watch(n, e.key)
        if (old && old !== n)
            old.dismiss()
        entries = prune([e, ...entries.filter(o => o !== same)])
        save()
    }

    // The app's object, while it keeps it: what it changes (replaces_id)
    // comes to the copy, at once.
    property var dirty: ({})

    function watch(n, key) {
        live = Object.assign({}, live, { [key]: n })
        n.closed.connect(() => notifications.forget(key, n))
        const changed = () => notifications.changed(key, n)
        n.summaryChanged.connect(changed)
        n.bodyChanged.connect(changed)
        n.appIconChanged.connect(changed)
        n.imageChanged.connect(changed)
        n.urgencyChanged.connect(changed)
        n.hintsChanged.connect(changed)
        n.expireTimeoutChanged.connect(changed)
    }
    function forget(key, n) {
        if (live[key] !== n)
            return
        const l = Object.assign({}, live)
        delete l[key]
        live = l
    }
    function changed(key, n) {
        if (live[key] !== n)
            return
        dirty[key] = n
        Qt.callLater(notifications.refresh)
    }
    // New words show it again (Spotify's next song), the newest; the rest
    // only changes it.
    function refresh() {
        const objects = dirty
        dirty = ({})
        const now = Date.now()
        let list = entries
        for (const key of Object.keys(objects)) {
            const old = list.find(o => o.key === key)
            if (!old || live[key] !== objects[key])
                continue
            const e = Object.assign({}, old, copy(objects[key]), { group: old.group })
            const news = e.summary !== old.summary || e.body !== old.body
            if (news) {
                e.time = now
                e.popup = e.popup || !dnd || e.critical
            }
            if (e.popup && (news || e.timeout !== old.timeout))
                e.until = e.timeout > 0 ? now + e.timeout : 0
            list = news ? [e, ...list.filter(o => o !== old)] : list.map(o => o === old ? e : o)
        }
        entries = list
        save()
    }

    // The popups' clock: what's due goes to the history (a transient one
    // goes). The pointer on the popups stops it; then each gets back the
    // time it had.
    property bool hovered: false
    property real pausedAt: 0
    onHoveredChanged: {
        const now = Date.now()
        if (hovered) {
            pausedAt = now
            return
        }
        entries = entries.map(e => e.popup && e.until > 0 ? Object.assign({}, e, {
            until: e.until + now - Math.max(pausedAt, e.time)
        }) : e)
        save()
    }
    function tick() {
        const now = Date.now()
        retire(entries.filter(e => e.popup && e.until > 0 && e.until <= now))
    }
    function retire(list) {
        if (list.length === 0)
            return
        for (const e of list)
            if (e.transient && live[e.key])
                live[e.key].expire()
        entries = entries.filter(e => !(e.transient && list.includes(e))).map(e => list.includes(e) ? Object.assign({}, e, {
            popup: false,
            until: 0
        }) : e)
        save()
    }

    Timer {
        running: !notifications.hovered && notifications.entries.some(e => e.popup && e.until > 0)
        interval: 200
        repeat: true
        onTriggered: notifications.tick()
    }

    // What leaves the list: the apps are told (dismissed) if they still
    // keep them.
    function drop(list) {
        if (list.length === 0)
            return
        entries = entries.filter(e => !list.includes(e))
        for (const e of list)
            if (live[e.key])
                live[e.key].dismiss()
        save()
    }
    function dismiss(e) {
        drop(entries.filter(o => o.key === e.key))
    }
    function clear() {
        drop(entries)
    }
    function clearGroup(group) {
        drop(entries.filter(e => e.group === group))
    }
    // The bell opens: all is seen, the popups go to its list (not critical
    // ones: they stay until dismissed).
    function seen() {
        seenAt = Date.now()
        retire(entries.filter(e => e.popup && !e.critical))
        save()
    }

    // The last 100 of the last day, besides those on screen.
    function prune(list) {
        const now = Date.now()
        const out = []
        let count = 0
        for (const e of list) {
            if (e.popup || (count < keep && now - e.time < keepFor)) {
                out.push(e)
                if (!e.popup)
                    count++
            } else if (live[e.key]) {
                live[e.key].dismiss()
            }
        }
        return out
    }
    Timer {
        running: true
        interval: 10 * 60 * 1000
        repeat: true
        onTriggered: {
            const list = notifications.prune(notifications.entries)
            if (list.length !== notifications.entries.length) {
                notifications.entries = list
                notifications.save()
            }
        }
    }

    // A click: the app's default action, else its file, else its window.
    // Done, it leaves the list (the app's action dismisses it, unless it's
    // resident).
    function activate(e) {
        const n = live[e.key]
        const action = n ? n.actions.find(a => a.identifier === "default") : null
        if (action) {
            invoke(e, action)
            return
        }
        const file = e.files.find(u => kept(u))
        if (file)
            Quickshell.execDetached(["xdg-open", file])
        else
            showApp(e)
        dismiss(e)
    }
    function invoke(e, action) {
        action.invoke()
        if (!e.resident) {
            entries = entries.filter(o => o.key !== e.key)
            save()
        }
    }
    function open(e, url) {
        Quickshell.execDetached(["xdg-open", url])
        dismiss(e)
    }
    function reveal(e, url) {
        Quickshell.execDetached(["nautilus", "--select", url])
        dismiss(e)
    }

    // The app's window, focused through Hyprland's dispatcher until it is
    // (from the bell's popup, once its grab lets go: 300 ms at most), else
    // the app, started through Hyprland as the launcher does.
    property var focusTarget: null

    function showApp(e) {
        const desktop = (e.entry ? DesktopEntries.byId(e.entry) : null) ?? (e.app ? DesktopEntries.heuristicLookup(e.app) : null)
        const names = [e.entry, e.app, desktop ? desktop.id : "", desktop ? desktop.startupClass : ""].filter(s => s).map(s => s.toLowerCase().replace(/\.desktop$/, ""))
        const window = Hyprland.toplevels.values.find(t => t.wayland && names.includes(t.wayland.appId.toLowerCase()))
        if (window) {
            focusTarget = window
            focusing.restart()
        } else if (desktop) {
            const command = desktop.command.filter(a => !/^%[fFuUdDnNickvm]$/.test(a)).map(a => "'" + a.replace(/'/g, "'\\''") + "'").join(" ")
            Quickshell.execDetached(["hyprctl", "eval", `hl.exec_cmd([==[${command}]==])`])
        }
    }
    Timer {
        id: focusing

        property int tries: 0

        interval: 30
        repeat: true
        onRunningChanged: tries = 0
        onTriggered: {
            const t = notifications.focusTarget
            if (t && !t.activated && ++tries <= 10) {
                Hyprland.dispatch(`hl.dsp.focus({ window = 'address:0x${t.address}' })`)
                return
            }
            stop()
            notifications.focusTarget = null
        }
    }

    // The history's file, read once at the start, then written half a
    // second after a change (once for a burst), never before it's read.
    // The apps' objects kept across a reload wait for it, to find their
    // copies.
    property bool restored: false
    property var retained: []

    function save() {
        if (restored && !saving.running)
            saving.start()
    }
    function restore() {
        if (restored)
            return
        const now = Date.now()
        // the adapter gives a Qt list, not an array (Array.isArray says no):
        // plain arrays and objects through JSON
        let list = []
        try {
            list = JSON.parse(JSON.stringify(stored.entries || []))
        } catch (e) {}
        if (!Array.isArray(list))
            list = []
        const known = entries.map(e => e.key)
        const back = list.filter(e => e && typeof e.key === "string" && typeof e.group === "string" && typeof e.time === "number" && typeof e.summary === "string" && !known.includes(e.key) && !brief.includes(e.app)).map(e => Object.assign({
                app: "",
                icon: "",
                body: "",
                files: [],
                count: 1,
                timeout: 0
            }, e, {
                picture: "",
                // back on screen with the time it had left; a critical one
                // stays
                popup: e.popup === true && (e.critical === true || e.until > now),
                until: e.popup === true && e.critical !== true ? e.until : 0
            }))
        entries = prune([...entries, ...back].sort((a, b) => b.time - a.time))
        seenAt = Math.max(seenAt, stored.seenAt || 0)
        if (stored.dnd)
            dnd = true
        restored = true
        for (const n of retained)
            reattach(n)
        retained = []
        save()
    }
    function reattach(n) {
        if (!restored) {
            retained.push(n)
            return
        }
        const e = entries.find(o => o.id === n.id && o.app === n.appName && !live[o.key])
        if (e)
            watch(n, e.key)
        else
            arrive(n, true)
    }

    FileView {
        id: store

        path: Quickshell.statePath("notifications.json")
        onLoaded: notifications.restore()
        // none yet, or unreadable: from nothing
        onLoadFailed: notifications.restore()

        JsonAdapter {
            id: stored

            property var entries: []
            property real seenAt: 0
            property bool dnd: false
        }
    }
    Timer {
        id: saving

        interval: 500
        onTriggered: {
            stored.entries = notifications.entries.filter(e => !e.transient).map(e => {
                const c = Object.assign({}, e)
                delete c.picture
                return c
            })
            stored.seenAt = notifications.seenAt
            stored.dnd = notifications.dnd
            store.writeAdapter()
        }
    }

    NotificationServer {
        id: server

        keepOnReload: true
        actionsSupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        persistenceSupported: true
        extraHints: ["x-kde-urls"]
        onNotification: n => {
            n.tracked = true
            if (n.lastGeneration)
                notifications.reattach(n)
            else
                notifications.arrive(n, false)
        }
    }

    PanelWindow {
        screen: notifications.screen
        visible: notifications.stacks.length > 0
        // gone from under the pointer: no leave comes
        onVisibleChanged: {
            if (!visible)
                notifications.hovered = false
        }
        anchors {
            bottom: true
            right: true
        }
        margins {
            bottom: 8
            right: 8
        }
        exclusiveZone: 0
        implicitWidth: 380
        implicitHeight: column.implicitHeight
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shadesmar-notifications"

        Column {
            id: column

            width: parent.width
            spacing: 8

            HoverHandler {
                onHoveredChanged: notifications.hovered = hovered
            }

            // kept while the list changes: their hover, their pictures
            Repeater {
                model: ScriptModel {
                    values: notifications.stacks
                    objectProp: "key"
                }

                NotificationStack {
                    required property var modelData

                    host: notifications
                    group: modelData.key
                    width: column.width
                }
            }
        }
    }
}
