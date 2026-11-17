// Claude Code's limits, as Omarchy's agents panel has them for one account:
// the 5-hour session's and the week's use (and a spend limit, behind a
// gateway that sets one), as Claude Code hands them to its status line,
// which writes them to ~/.local/state/claude/limits.json at each reply
// (modules/claude's statusline-command.sh): nothing here holds a token or
// asks Anthropic. Hidden until Claude Code has written them once.
//
// The bar (beside the desktops): Claude's spark, the session's and the
// week's use, a window red from 90 % (the spark too). The popup: a meter for
// each window, a tick where an even pace would be, the time until it starts
// again, and how old the numbers are (as fresh as the last reply); Reload
// reads the file again at once.
import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: claude

    property var limits: null
    // seconds, a minute's precision: the resets and the age count down
    property real now: Date.now() / 1000

    // Read again with the clock: the status line replaces the file at each
    // write (a rename), and a file that wasn't there yet can't be watched;
    // the watch is only the quick way.
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: {
            claude.now = Date.now() / 1000
            limitsFile.reload()
        }
    }

    FileView {
        id: limitsFile

        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/claude/limits.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                claude.limits = JSON.parse(text())
            } catch (e) {
                claude.limits = null
            }
            claude.now = Date.now() / 1000
        }
        onLoadFailed: claude.limits = null
    }

    // A window: {used (0-100), resets (epoch seconds), pace (0-1, -1 when
    // unknown)}. One whose reset has passed starts again from nothing.
    function window(key, length) {
        const w = limits ? limits[key] : null
        if (!w || typeof w.used_percentage !== "number")
            return null
        const resets = w.resets_at || 0
        if (resets > 0 && resets <= now)
            return { used: 0, resets: 0, pace: -1, length: length }
        return {
            used: Math.max(0, w.used_percentage),
            resets: resets,
            pace: resets > 0 && length > 0 ? Math.max(0, Math.min(1, 1 - (resets - now) / length)) : -1,
            length: length
        }
    }

    readonly property var session: window("five_hour", 5 * 3600)
    readonly property var week: window("seven_day", 7 * 86400)
    // a gateway's: its period's length isn't said, so no pace
    readonly property var spend: window("spend_limit", 0)
    readonly property bool high: [session, week, spend].some(w => w && w.used >= 90)

    // "3d 4h", "2h 13m", "42m"
    function span(seconds) {
        const m = Math.max(1, Math.round(seconds / 60))
        const d = Math.floor(m / 1440), h = Math.floor(m % 1440 / 60), mm = m % 60
        return d > 0 ? `${d}d ${h}h` : h > 0 ? `${h}h ${mm}m` : `${mm}m`
    }

    readonly property string age: {
        if (!limits || !limits.at)
            return ""
        // in words: the caption is in capitals, where "3M" reads as months
        const m = Math.round((now - limits.at) / 60)
        return m < 2 ? "Updated just now" : m < 60 ? `Updated ${m} min ago` : m < 2880 ? `Updated ${Math.round(m / 60)} h ago` : `Updated ${Math.round(m / 1440)} days ago`
    }

    visible: limits !== null
    popup: "claude"
    iconSource: Qt.resolvedUrl("icons/claude.svg")
    iconColor: high ? Theme.warn : Theme.text
    // "5h 14% · 7d 19%", the names dim as in the status line, a window red
    // from 90 %
    function part(name, w) {
        if (!w)
            return ""
        const n = Math.round(w.used)
        return `<font color="${Theme.dim}">${name}</font> ${n >= 90 ? `<font color="${Theme.warn}">${n}%</font>` : `${n}%`}`
    }
    label: [part("5h", session), part("7d", week)].filter(p => p !== "").join(` <font color="${Theme.dim}">·</font> `)
    labelColor: Theme.text

    // a window's line: its name and use, the meter, its length and reset
    component Limit: Column {
        id: limit

        property string title: ""
        property string detail: ""
        property var w: null
        property string amount: w ? `${Math.round(w.used)}%` : ""

        width: parent ? parent.width : 300
        leftPadding: 4
        rightPadding: 4
        topPadding: 4
        bottomPadding: 6
        spacing: 6

        Item {
            width: limit.width - 8
            height: name.implicitHeight

            Text {
                id: name

                text: limit.title
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: 13
            }

            Text {
                anchors.right: parent.right
                text: limit.amount
                color: limit.w && limit.w.used >= 90 ? Theme.warn : Theme.text
                font.family: Theme.font
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
        }

        Meter {
            width: limit.width - 8
            value: limit.w ? limit.w.used / 100 : 0
            pace: limit.w ? limit.w.pace : -1
        }

        Item {
            width: limit.width - 8
            height: left.implicitHeight

            Text {
                id: left

                text: limit.detail
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11
            }

            Text {
                anchors.right: parent.right
                text: !limit.w ? "" : limit.w.resets > 0 ? `resets in ${claude.span(limit.w.resets - claude.now)}` : "not started"
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: 11
            }
        }
    }

    BarPopup {
        id: popup

        bar: claude.bar
        from: claude
        name: "claude"
        popupWidth: 340
        onShownChanged: {
            if (shown)
                claude.now = Date.now() / 1000
        }

        PopupHero {
            iconSource: Qt.resolvedUrl("icons/claude.svg")
            title: "Claude Code"
            caption: claude.high ? `Near the limit · ${claude.age}` : claude.age
            warn: claude.high
        }

        SectionLabel {
            text: "Limits"
        }

        Limit {
            visible: claude.session !== null
            title: "Session"
            detail: "5-hour window"
            w: claude.session
        }

        Limit {
            visible: claude.week !== null
            title: "Week"
            detail: "7-day window, all models"
            w: claude.week
        }

        Limit {
            visible: claude.spend !== null
            title: "Spend"
            detail: claude.limits && claude.limits.spend_limit && claude.limits.spend_limit.period ? claude.limits.spend_limit.period : "spend limit"
            w: claude.spend
            amount: {
                const s = claude.limits ? claude.limits.spend_limit : null
                return s && typeof s.used_usd === "number" && typeof s.limit_usd === "number" ? `$${Math.round(s.used_usd)} of $${Math.round(s.limit_usd)}` : w ? `${Math.round(w.used)}%` : ""
            }
        }

        Text {
            visible: claude.session === null && claude.week === null && claude.spend === null
            width: parent.width
            leftPadding: 4
            text: "Claude Code hasn't said anything about its limits since they last reset."
            wrapMode: Text.Wrap
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
        }

        Item {
            width: 1
            height: 4
        }

        // the file now rather than at the next half minute: the numbers
        // themselves are new at Claude Code's next reply
        ListRow {
            lineIcon: Qt.resolvedUrl("icons/refresh-cw.svg")
            title: "Reload"
            subtitle: "Claude Code's latest numbers"
            onClicked: {
                limitsFile.reload()
                claude.now = Date.now() / 1000
            }
        }
    }
}
