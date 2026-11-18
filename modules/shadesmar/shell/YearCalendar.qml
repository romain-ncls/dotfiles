// The year as the post office's calendar prints it (Almanac.js), half a
// year at a time: six months side by side, a day a line (its weekday's
// letter, its number, its saint or its feast, the week's number on
// Mondays, the clock's change), Saturdays and Sundays shaded, the days off
// in red, today outlined, and the school holidays of zones A, B and C as
// stripes (the ministry's open data, data.education.gouv.fr, kept a week in
// the shell's cache). The line under the pointer is spelled out at the
// bottom. From the clock's popup (Clock.qml), or qs -c shadesmar ipc call
// calendar toggle. Left/Right, the chevrons or the wheel: the half before
// or after; Home: today's; Escape or a click outside closes.
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "Almanac.js" as Almanac

Scope {
    id: calendar

    property bool shown: false
    property int year: 2000
    property int half: 0 // 0: January to June, 1: July to December
    property var hovered: null // the day under the pointer
    readonly property var locale: Qt.locale((Quickshell.env("LC_TIME") || Quickshell.env("LANG") || "C").split(".")[0])

    function open() {
        home()
        hovered = null
        shown = true
        school.want(year)
    }
    function close() {
        shown = false
    }
    function toggle() {
        if (shown)
            close()
        else
            open()
    }
    function home() {
        const d = new Date()
        year = d.getFullYear()
        half = d.getMonth() < 6 ? 0 : 1
    }
    function step(n) {
        const h = half + n
        year += Math.floor(h / 2)
        half = (h % 2 + 2) % 2
    }
    onYearChanged: {
        if (shown)
            school.want(year)
    }

    function capital(s) {
        return s.charAt(0).toUpperCase() + s.slice(1)
    }
    function dayKey(d) {
        return `${d.getFullYear()}-${Almanac.key(d)}`
    }

    IpcHandler {
        target: "calendar"

        function toggle(): void {
            calendar.toggle()
        }
    }

    // The school holidays: {"YYYY-MM-DD": [{zone, name}]}, from the periods
    // of the school years around the year shown, asked once a week.
    QtObject {
        id: school

        readonly property var zones: ["A", "B", "C"]
        readonly property var colors: ({ A: "#f08ab5", B: "#eebc4a", C: "#48b7bd" })
        // {"2026-2027": {fetched, periods: [{zone, from, to, name}]}}
        property var years: ({})
        property bool loaded: false
        property var asking: ({})

        readonly property var days: {
            const out = {}
            for (const sy in years) {
                for (const p of years[sy].periods) {
                    const from = new Date(p.from + "T12:00:00"), to = new Date(p.to + "T12:00:00")
                    for (let d = from; d < to || d.getTime() === from.getTime(); d = Almanac.plus(d, 1)) {
                        const k = calendar.dayKey(d)
                        if (!out[k])
                            out[k] = []
                        if (!out[k].some(x => x.zone === p.zone))
                            out[k].push({ zone: p.zone, name: p.name })
                    }
                }
            }
            return out
        }

        // the school years that touch a calendar year
        function want(y) {
            if (!loaded)
                return
            for (const sy of [`${y - 1}-${y}`, `${y}-${y + 1}`]) {
                const have = years[sy]
                if ((!have || Date.now() - have.fetched > 7 * 86400000) && !asking[sy])
                    fetch(sy)
            }
        }

        // local dates: the ministry gives each period from the midnight its
        // first day starts at to the one classes start again at, in UTC
        function local(iso) {
            const d = new Date(iso)
            return `${d.getFullYear()}-${Almanac.pad(d.getMonth() + 1)}-${Almanac.pad(d.getDate())}`
        }

        function fetch(sy) {
            asking[sy] = true
            const where = `annee_scolaire="${sy}" and (zones="Zone A" or zones="Zone B" or zones="Zone C") and population!="Enseignants"`
            const url = "https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/fr-en-calendrier-scolaire/records"
                + "?select=" + encodeURIComponent("description,start_date,end_date,zones")
                + "&where=" + encodeURIComponent(where)
                + "&group_by=" + encodeURIComponent("description,start_date,end_date,zones")
                + "&limit=100"
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                asking[sy] = false
                if (xhr.status !== 200)
                    return
                try {
                    const periods = JSON.parse(xhr.responseText).results.map(r => {
                        const from = local(r.start_date)
                        let to = local(r.end_date)
                        // a one-day bridge comes as nothing long
                        if (to <= from)
                            to = local(new Date(new Date(r.start_date).getTime() + 86400000).toISOString())
                        return { zone: r.zones.replace("Zone ", ""), from: from, to: to, name: r.description }
                    })
                    const next = Object.assign({}, years)
                    next[sy] = { fetched: Date.now(), periods: periods }
                    years = next
                    cache.setText(JSON.stringify(next))
                } catch (e) {}
            }
            xhr.open("GET", url)
            xhr.send()
        }
    }

    FileView {
        id: cache

        path: Quickshell.cachePath("school-holidays.json")
        printErrors: false
        onLoaded: {
            try {
                school.years = JSON.parse(text())
            } catch (e) {}
            school.loaded = true
            if (calendar.shown)
                school.want(calendar.year)
        }
        onLoadFailed: {
            school.loaded = true
            if (calendar.shown)
                school.want(calendar.year)
        }
    }

    PanelWindow {
        id: window

        screen: {
            const m = Hyprland.focusedMonitor
            return Quickshell.screens.find(s => m && s.name === m.name) ?? Quickshell.screens[0]
        }
        visible: calendar.shown
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        // Hyprland blurs behind the panel, not the clear margins (lumar.lua)
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "shadesmar-calendar"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        MouseArea {
            anchors.fill: parent
            onClicked: calendar.close()
        }

        Rectangle {
            id: panel

            // concentric: the months' heads' corners, inside the panel's
            readonly property int pad: Theme.overlayCorner - Theme.corner
            readonly property int gap: Theme.pad
            readonly property real column: (width - 2 * pad - 5 * gap) / 6
            // 31 lines between the head, the months' names and the foot
            readonly property int row: Math.max(18, Math.floor((height - 2 * pad - head.height - 34 - foot.height - 12) / 31))

            anchors.centerIn: parent
            width: Math.min(parent.width - 64, 1760)
            height: Math.min(parent.height - 64, 1040)
            radius: Theme.overlayCorner
            color: Theme.reading
            border.width: 1
            border.color: Theme.outline

            // clicks inside stay inside; the wheel steps
            property real wheel: 0

            MouseArea {
                anchors.fill: parent
                onWheel: event => {
                    panel.wheel += event.angleDelta.y
                    while (Math.abs(panel.wheel) >= 120) {
                        calendar.step(panel.wheel > 0 ? -1 : 1)
                        panel.wheel -= panel.wheel > 0 ? 120 : -120
                    }
                }
            }

            Item {
                anchors.fill: parent
                focus: calendar.shown
                Keys.onEscapePressed: calendar.close()
                Keys.onLeftPressed: calendar.step(-1)
                Keys.onRightPressed: calendar.step(1)
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) {
                        calendar.home()
                        event.accepted = true
                    }
                }
            }

            // the year and the half shown; the steps, today, close
            Item {
                id: head

                x: panel.pad
                y: panel.pad - 4
                width: panel.width - 2 * panel.pad
                height: 44

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    Text {
                        id: yearText

                        text: calendar.year
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: Theme.large
                        font.weight: Font.Medium
                    }

                    Text {
                        anchors.baseline: yearText.baseline
                        text: `${calendar.capital(calendar.locale.standaloneMonthName(calendar.half * 6, Locale.LongFormat))} – ${calendar.capital(calendar.locale.standaloneMonthName(calendar.half * 6 + 5, Locale.LongFormat))}`
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.title
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        rightPadding: 10
                        text: "Aujourd'hui"
                        color: todayLink.containsMouse ? Theme.accent : Theme.dim
                        font.family: Theme.font
                        font.pixelSize: Theme.body

                        MouseArea {
                            id: todayLink

                            anchors.fill: parent
                            anchors.margins: -4
                            hoverEnabled: true
                            onClicked: calendar.home()
                        }
                    }

                    Chevron {
                        icon: "chevron-left"
                        onClicked: calendar.step(-1)
                    }
                    Chevron {
                        icon: "chevron-right"
                        onClicked: calendar.step(1)
                    }
                    Item {
                        width: 8
                        height: 1
                    }
                    Chevron {
                        icon: "x"
                        onClicked: calendar.close()
                    }
                }
            }

            // the six months
            Row {
                id: months

                x: panel.pad
                y: head.y + head.height + 8
                spacing: panel.gap

                Repeater {
                    model: 6

                    Column {
                        id: month

                        required property int index
                        readonly property int number: calendar.half * 6 + index
                        readonly property int length: new Date(calendar.year, number + 1, 0).getDate()

                        width: panel.column
                        spacing: 0

                        Rectangle {
                            width: parent.width
                            height: 28
                            radius: Theme.corner
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: calendar.locale.standaloneMonthName(month.number, Locale.LongFormat).toUpperCase()
                                color: Theme.accentText
                                font.family: Theme.font
                                font.pixelSize: Theme.body
                                font.weight: Font.Bold
                                font.letterSpacing: 1
                            }
                        }

                        Item {
                            width: 1
                            height: 6
                        }

                        Repeater {
                            model: month.length

                            Rectangle {
                                id: line

                                required property int index
                                readonly property var date: Almanac.day(calendar.year, month.number, index + 1)
                                readonly property var info: Almanac.label(date)
                                readonly property bool off: info.kind === "holiday"
                                readonly property int weekday: date.getDay()
                                readonly property bool today: Almanac.key(date) === Almanac.key(new Date()) && date.getFullYear() === new Date().getFullYear()
                                readonly property var zones: school.days[calendar.dayKey(date)] || []
                                readonly property string change: Almanac.clockChange(date)
                                readonly property color ink: off ? Theme.accentText : Theme.text

                                width: month.width
                                height: panel.row
                                radius: 4
                                color: off ? Theme.warn : weekday === 0 ? Theme.alpha(Theme.textColor, 0.10) : weekday === 6 ? Theme.alpha(Theme.textColor, 0.05) : hover.containsMouse ? Theme.hover : "transparent"
                                border.width: today ? 2 : 0
                                border.color: Theme.accent

                                Text {
                                    x: 6
                                    width: 12
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: calendar.locale.dayName(line.weekday, Locale.NarrowFormat)
                                    color: line.off ? line.ink : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.small
                                }

                                Text {
                                    x: 18
                                    width: 22
                                    anchors.verticalCenter: parent.verticalCenter
                                    horizontalAlignment: Text.AlignRight
                                    text: line.date.getDate()
                                    color: line.ink
                                    font.family: Theme.font
                                    font.pixelSize: Theme.body
                                    font.weight: Font.Bold
                                }

                                Text {
                                    x: 48
                                    width: right.x - x - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: line.info.name
                                    elide: Text.ElideRight
                                    color: line.ink
                                    font.family: Theme.font
                                    font.pixelSize: Theme.body
                                    font.weight: line.info.kind !== "" ? Font.Bold : Font.Normal
                                }

                                // the week's number on Mondays, the clock's change
                                Text {
                                    id: right

                                    x: stripes.x - width - 6
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: line.change !== "" ? line.change : line.weekday === 1 ? Almanac.pad(Almanac.isoWeek(line.date)) : ""
                                    color: line.change !== "" ? (line.off ? line.ink : Theme.accent) : line.off ? line.ink : Theme.dim
                                    font.family: Theme.font
                                    font.pixelSize: Theme.small
                                    font.italic: line.change === ""
                                    font.weight: line.change !== "" ? Font.Medium : Font.Normal
                                }

                                // the school holidays: a stripe a zone
                                Row {
                                    id: stripes

                                    anchors.right: parent.right
                                    anchors.rightMargin: 3
                                    height: parent.height
                                    spacing: 2

                                    Repeater {
                                        model: school.zones

                                        Rectangle {
                                            required property string modelData

                                            width: 4
                                            height: parent.height
                                            color: line.zones.some(z => z.zone === modelData) ? school.colors[modelData] : "transparent"
                                        }
                                    }
                                }

                                MouseArea {
                                    id: hover

                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onContainsMouseChanged: {
                                        if (containsMouse)
                                            calendar.hovered = line.date
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // the day under the pointer (today's otherwise), spelled out;
            // the key
            Item {
                id: foot

                x: panel.pad
                anchors.bottom: parent.bottom
                anchors.bottomMargin: panel.pad - 4
                width: panel.width - 2 * panel.pad
                height: 24

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: legend.x - 16
                    elide: Text.ElideRight
                    text: {
                        const d = calendar.hovered ?? new Date()
                        const info = Almanac.label(d)
                        const parts = [calendar.capital(d.toLocaleDateString(calendar.locale, "dddd d MMMM yyyy"))]
                        if (info.kind !== "")
                            parts.push(info.name)
                        for (const a of info.also)
                            parts.push(a)
                        if (info.saint !== "" && info.saint !== info.name)
                            parts.push(`fête : ${info.saint}`)
                        else if (info.kind === "")
                            parts.push(`fête : ${info.name}`)
                        const zones = school.days[calendar.dayKey(d)] || []
                        if (zones.length > 0)
                            parts.push(`${zones[0].name} (zone${zones.length > 1 ? "s" : ""} ${zones.map(z => z.zone).join(", ")})`)
                        const change = Almanac.clockChange(d)
                        if (change !== "")
                            parts.push(`changement d'heure (${change})`)
                        return parts.join("  ·  ")
                    }
                    color: Theme.text
                    font.family: Theme.font
                    font.pixelSize: Theme.body
                }

                Row {
                    id: legend

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 16

                    Row {
                        spacing: 6

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12
                            height: 12
                            radius: 3
                            color: Theme.warn
                        }
                        Text {
                            text: "Jour férié"
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: Theme.small
                        }
                    }

                    Repeater {
                        model: school.zones

                        Row {
                            required property string modelData

                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4
                                height: 14
                                color: school.colors[modelData]
                            }
                            Text {
                                text: `Zone ${modelData}`
                                color: Theme.dim
                                font.family: Theme.font
                                font.pixelSize: Theme.small
                            }
                        }
                    }
                }
            }
        }
    }
}
