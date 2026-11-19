// The time, and the date under it, as Plasma's clock has them. Its popup,
// as Omarchy's clock: today, big (the time to the second while it's open,
// the date in full), and a month with ISO week numbers, stepped with the
// chevrons, the wheel or the arrow keys (PageUp/PageDown a year; Home, or a
// click on the month's name or today's date, comes back). A read-out, not a
// picker: today is the one day marked, the days off in red (Almanac.js),
// and under the month its days off and feasts; today's saint in the
// caption. The button at the top opens the whole year (YearCalendar.qml).
// The names and the week's first day are LC_TIME's (French here), as the
// dates elsewhere on the desktop.
import QtQuick
import Quickshell
import "Almanac.js" as Almanac

BarItem {
    id: root

    property var yearView: null // YearCalendar.qml
    readonly property var locale: Qt.locale((Quickshell.env("LC_TIME") || Quickshell.env("LANG") || "C").split(".")[0])

    implicitWidth: column.implicitWidth + 14
    open: popup.shown
    onClicked: root.bar.open = popup.shown ? "" : "clock"

    SystemClock {
        id: clock

        precision: popup.shown ? SystemClock.Seconds : SystemClock.Minutes
    }

    function capital(s) {
        return s.charAt(0).toUpperCase() + s.slice(1)
    }

    Column {
        id: column

        anchors.centerIn: parent

        Digits {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "HH:mm")
            weight: Font.Medium
        }

        Digits {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "dd/MM/yyyy")
            color: Theme.dim
            size: Theme.small
        }
    }

    BarPopup {
        id: popup

        bar: root.bar
        from: root
        name: "clock"
        popupWidth: 320

        // the month on screen
        property int year: 2000
        property int month: 0

        // the month changing: its days come from the side it goes to
        function slide(months) {
            if (months === 0)
                return
            shift.x = months > 0 ? 12 : -12
            grid.opacity = 0.4
            slideIn.restart()
        }
        function home() {
            popup.year = clock.date.getFullYear()
            popup.month = clock.date.getMonth()
        }
        // back to this month, from the one shown
        function back() {
            const months = (clock.date.getFullYear() - popup.year) * 12 + clock.date.getMonth() - popup.month
            home()
            slide(months)
        }
        function step(months) {
            const d = new Date(popup.year, popup.month + months, 1, 12)
            popup.year = d.getFullYear()
            popup.month = d.getMonth()
            slide(months)
        }

        onShownChanged: {
            if (shown)
                home()
        }

        // today: the time, the date, the week and the day of the year
        Item {
            width: parent.width
            height: 96

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 4

                Text {
                    id: bigTime

                    text: Qt.formatDateTime(clock.date, "HH:mm")
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.display
                    font.weight: Font.Medium
                }

                Text {
                    anchors.baseline: bigTime.baseline
                    text: Qt.formatDateTime(clock.date, ":ss")
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: Theme.large
                    font.weight: Font.Medium
                }
            }

            Text {
                id: longDate

                anchors.horizontalCenter: parent.horizontalCenter
                y: 56
                text: root.capital(clock.date.toLocaleDateString(root.locale, "dddd d MMMM yyyy"))
                color: today.containsMouse ? Theme.accent : Theme.text
                font.family: Theme.font
                font.pixelSize: Theme.body

                MouseArea {
                    id: today

                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    onClicked: popup.back()
                }
            }

            // the week, the day of the year, today's saint (or feast)
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                y: 76
                text: {
                    const d = clock.date
                    const start = new Date(d.getFullYear(), 0, 1, 12)
                    const day = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12) - start) / 86400000) + 1
                    return `Week ${calendar.isoWeek(d)} · day ${day} · ${Almanac.label(d).name}`.toUpperCase()
                }
                color: Theme.dim
                font.family: Theme.font
                font.pixelSize: Theme.small
                font.weight: Font.Medium
                font.letterSpacing: 1
            }

            // the whole year
            Chevron {
                visible: root.yearView !== null
                anchors.right: parent.right
                y: 0
                icon: "calendar-range"
                onClicked: {
                    popup.close()
                    root.yearView.open()
                }
            }
        }

        Item {
            id: calendar

            width: parent.width
            height: head.height + grid.height + 6
            focus: true

            // on a plate, as the other popups' groups
            Rectangle {
                anchors.fill: parent
                radius: Theme.plateCorner
                color: Theme.plate
            }

            // the cells' width: the week's number and seven days
            readonly property real cell: Math.floor(width / 8)
            readonly property int first: root.locale.firstDayOfWeek // 0 Sunday
            readonly property var start: {
                const d = new Date(popup.year, popup.month, 1, 12)
                return new Date(popup.year, popup.month, 1 - (d.getDay() - first + 7) % 7, 12)
            }

            function day(n) {
                return new Date(start.getFullYear(), start.getMonth(), start.getDate() + n, 12)
            }
            // ISO 8601: the week of its Thursday, counted from the year's
            // first Thursday's
            function isoWeek(d) {
                const t = new Date(d.getFullYear(), d.getMonth(), d.getDate() - (d.getDay() + 6) % 7 + 3, 12)
                const jan4 = new Date(t.getFullYear(), 0, 4, 12)
                const thu1 = new Date(t.getFullYear(), 0, 4 - (jan4.getDay() + 6) % 7 + 3, 12)
                return 1 + Math.round((t - thu1) / (7 * 86400000))
            }
            function same(a, b) {
                return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
            }

            Keys.onLeftPressed: popup.step(-1)
            Keys.onRightPressed: popup.step(1)
            Keys.onUpPressed: popup.step(-1)
            Keys.onDownPressed: popup.step(1)
            Keys.onPressed: event => {
                if (event.key === Qt.Key_PageUp)
                    popup.step(-12)
                else if (event.key === Qt.Key_PageDown)
                    popup.step(12)
                else if (event.key === Qt.Key_Home)
                    popup.home()
                else
                    return
                event.accepted = true
            }

            // the wheel, a notch a month (a touchpad's small steps add up)
            property real wheel: 0

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: event => {
                    calendar.wheel += event.angleDelta.y
                    while (Math.abs(calendar.wheel) >= 120) {
                        popup.step(calendar.wheel > 0 ? -1 : 1)
                        calendar.wheel -= calendar.wheel > 0 ? 120 : -120
                    }
                }
            }

            Item {
                id: head

                y: 6
                width: parent.width
                height: 32

                Chevron {
                    icon: "chevron-left"
                    onClicked: popup.step(-1)
                }

                Text {
                    anchors.centerIn: parent
                    text: `${root.capital(root.locale.standaloneMonthName(popup.month, Locale.LongFormat))} ${popup.year}`
                    color: title.containsMouse ? Theme.accent : Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.title
                    font.weight: Font.Medium

                    MouseArea {
                        id: title

                        anchors.fill: parent
                        anchors.margins: -4
                        hoverEnabled: true
                        onClicked: popup.home()
                    }
                }

                Chevron {
                    anchors.right: parent.right
                    icon: "chevron-right"
                    onClicked: popup.step(1)
                }
            }

            Grid {
                id: grid

                transform: Translate {
                    id: shift
                }

                ParallelAnimation {
                    id: slideIn

                    Ease {
                        target: shift
                        property: "x"
                        to: 0
                        easing.bezierCurve: Theme.move
                    }
                    Ease {
                        target: grid
                        property: "opacity"
                        to: 1
                        duration: Theme.fast
                        easing.bezierCurve: Theme.fade
                    }
                }

                y: head.y + head.height + 4
                columns: 8

                // the days' names: "Lu", "Ma"…
                Item {
                    width: calendar.cell
                    height: 26
                }

                Repeater {
                    model: 7

                    Text {
                        required property int index

                        width: calendar.cell
                        height: 26
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: root.capital(root.locale.dayName((calendar.first + index) % 7, Locale.ShortFormat).replace(".", "").slice(0, 2))
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.small
                        font.weight: Font.Medium
                    }
                }

                // six weeks, each its number then its days
                Repeater {
                    model: 48

                    Item {
                        id: cell

                        required property int index
                        readonly property int row: Math.floor(index / 8)
                        readonly property int column: index % 8
                        readonly property var date: column > 0 ? calendar.day(row * 7 + column - 1) : null
                        readonly property bool inMonth: date !== null && date.getMonth() === popup.month
                        readonly property bool isToday: date !== null && calendar.same(date, clock.date)
                        readonly property bool weekend: date !== null && (date.getDay() === 0 || date.getDay() === 6)
                        readonly property bool off: date !== null && Almanac.holiday(date)

                        width: calendar.cell
                        height: 34

                        Rectangle {
                            visible: cell.isToday
                            anchors.centerIn: parent
                            width: 30
                            height: 30
                            radius: height / 2
                            color: cell.off ? Theme.warn : Theme.accent
                        }

                        Text {
                            anchors.centerIn: parent
                            text: cell.column === 0 ? calendar.isoWeek(calendar.day(cell.row * 7)) : cell.date.getDate()
                            color: cell.isToday ? Theme.accentText : cell.off ? Theme.warn : cell.column === 0 || cell.weekend ? Theme.dim : Theme.text
                            opacity: cell.column === 0 ? 0.7 : cell.inMonth ? 1 : 0.35
                            font.family: Theme.font
                            font.pixelSize: cell.column === 0 ? Theme.small : Theme.body
                            font.weight: cell.isToday || cell.off ? Font.Bold : Font.Normal
                        }
                    }
                }
            }
        }

        // the month's days off and feasts: its number (red for a day off)
        // and its name
        Rectangle {
            visible: events.list.length > 0
            width: parent.width
            height: events.height
            radius: Theme.plateCorner
            color: Theme.plate

            Column {
                id: events

                readonly property var list: {
                    const out = []
                    const length = new Date(popup.year, popup.month + 1, 0).getDate()
                    for (let n = 1; n <= length; n++) {
                        const info = Almanac.label(Almanac.day(popup.year, popup.month, n))
                        if (info.kind === "holiday" || info.kind === "feast" && Almanac.FEASTS.indexOf(Almanac.key(Almanac.day(popup.year, popup.month, n))) < 0)
                            out.push({ day: n, name: info.name, off: info.kind === "holiday" })
                    }
                    return out
                }

                width: parent.width
                topPadding: 8
                bottomPadding: 8
                spacing: 2

                Repeater {
                    model: events.list

                    Row {
                        required property var modelData

                        spacing: 12

                        Text {
                            width: calendar.cell - 4
                            horizontalAlignment: Text.AlignRight
                            text: modelData.day
                            color: modelData.off ? Theme.warn : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.small
                            font.weight: Font.Bold
                        }

                        Text {
                            text: modelData.name
                            color: modelData.off ? Theme.text : Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.small
                        }
                    }
                }
            }
        }
    }
}
