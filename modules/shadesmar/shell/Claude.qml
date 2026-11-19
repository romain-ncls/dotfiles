// Claude Code's limits, as Omarchy's agents panel has them for one account:
// the 5-hour session's and the week's use (and a spend limit, behind a
// gateway that sets one), as Claude Code hands them to its status line,
// which writes them to ~/.local/state/claude/limits.json at each reply
// (modules/claude's statusline-command.sh): nothing here holds a token or
// asks Anthropic. Hidden until Claude Code has written them once.
//
// The bar (beside the desktops): Claude's spark, then the session's and the
// week's use side by side (a ring filled as far, the number, or "not
// started"), red from 90 % (the spark too). The popup: a meter for each window, a tick where an even
// pace would be, the time until it starts again, and how old the numbers
// are (as fresh as the last reply); Reload, in its corner, reads the file
// again at once.
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
        // by its id: unqualified, reload() isn't found from inside this item
        onFileChanged: limitsFile.reload()
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

    // A window: {started, used (0-100), resets (epoch seconds), pace (0-1,
    // -1 when unknown)}. Claude Code leaves out a window with no use since
    // its last reset, and one whose reset has passed starts again from
    // nothing: the session and the week are still shown then, as not
    // started (`always`); a spend limit only behind a gateway that sets one.
    function window(key, length, always) {
        const w = limits ? limits[key] : null
        const idle = {
            started: false,
            used: 0,
            resets: 0,
            pace: -1,
            length: length
        }
        if (!w || typeof w.used_percentage !== "number")
            return limits && always ? idle : null
        const resets = w.resets_at || 0
        if (resets > 0 && resets <= now)
            return idle
        return {
            started: true,
            used: Math.max(0, w.used_percentage),
            resets: resets,
            pace: resets > 0 && length > 0 ? Math.max(0, Math.min(1, 1 - (resets - now) / length)) : -1,
            length: length
        }
    }

    readonly property var session: window("five_hour", 5 * 3600, true)
    readonly property var week: window("seven_day", 7 * 86400, true)
    // a gateway's: its period's length isn't said, so no pace
    readonly property var spend: window("spend_limit", 0, false)
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
    // side by side, as the bar's other items have theirs: a window's name
    // (dim), a ring filled as far as it's used (an icon's size), the number
    // (red from 90 %); the text the size of theirs, the gaps too
    extra: Component {
        Row {
            leftPadding: 2
            spacing: 14

            // the same two, kept (their rings glide, their numbers roll)
            Repeater {
                model: ["5h", "7d"]

                Row {
                    id: win

                    required property string modelData
                    readonly property var w: modelData === "5h" ? claude.session : claude.week
                    readonly property bool full: w !== null && w.used >= 90

                    visible: w !== null
                    spacing: 6

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.modelData
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.body
                    }

                    Ring {
                        anchors.verticalCenter: parent.verticalCenter
                        size: Theme.icon
                        value: win.w ? win.w.used / 100 : 0
                        color: win.full ? Theme.warn : Theme.accent
                    }

                    Digits {
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.w && win.w.started ? `${Math.round(win.w.used)}%` : "not started"
                        color: win.full ? Theme.warn : win.w && win.w.started ? Theme.text : Theme.dim
                    }
                }
            }
        }
    }

    // a window's line: its name and use, the meter, its length and reset
    component Limit: Column {
        id: limit

        property string title: ""
        property string detail: ""
        property var w: null
        property string amount: w ? `${Math.round(w.used)}%` : ""

        width: parent ? parent.width : 300
        leftPadding: 10
        rightPadding: 10
        topPadding: 8
        bottomPadding: 10
        spacing: 6

        Item {
            width: limit.width - 20
            height: name.implicitHeight

            Text {
                id: name

                text: limit.title
                color: Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.body
            }

            Text {
                anchors.right: parent.right
                text: limit.amount
                color: limit.w && limit.w.used >= 90 ? Theme.warn : Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.body
                font.weight: Font.Medium
            }
        }

        Meter {
            width: limit.width - 20
            value: limit.w ? limit.w.used / 100 : 0
            pace: limit.w ? limit.w.pace : -1
        }

        Item {
            width: limit.width - 20
            height: left.implicitHeight

            Text {
                id: left

                text: limit.detail
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.small
            }

            Text {
                anchors.right: parent.right
                text: !limit.w ? "" : !limit.w.started ? "not started" : limit.w.resets > 0 ? `resets in ${claude.span(limit.w.resets - claude.now)}` : ""
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.small
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

        // the head, and in its corner Reload: the file now rather than at the
        // next half minute (the numbers themselves are new at Claude Code's
        // next reply)
        Item {
            width: parent.width
            height: hero.height

            PopupHero {
                id: hero

                iconSource: Qt.resolvedUrl("icons/claude.svg")
                title: "Claude Code"
                caption: claude.high ? `Near the limit · ${claude.age}` : claude.age
                warn: claude.high
            }

            Chevron {
                id: reload

                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                icon: "refresh-cw"
                onClicked: {
                    reload.turn()
                    limitsFile.reload()
                    claude.now = Date.now() / 1000
                }
            }
        }

        Section {
            title: "Limits"

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
        }
    }
}
