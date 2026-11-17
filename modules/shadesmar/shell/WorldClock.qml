// The world clock, as Omarchy's Elsewhen: a city a row, with who lives
// there, its time and how far it is from here, the part of its day
// (morning, evening… is it a decent hour to call), its weather, and its day
// as a line, daylight lit, a dot where it is now. Cities are searched and
// added at the bottom (Open-Meteo's geocoding: type as it opens, Enter adds
// the first found), removed and given their people on hover; kept in the
// shell's state (worldclock.json). The time zones are the system's (`date`
// under each TZ: right across the clock changes, offline too); the weather
// and the sun are Open-Meteo's (no key), asked when the popup opens, at most
// every half hour. Not taken from Omarchy: its globe.
import QtQuick
import Quickshell
import Quickshell.Io

BarButton {
    id: world

    popup: "world"
    iconSource: Qt.resolvedUrl("icons/globe.svg")

    readonly property var locale: Qt.locale((Quickshell.env("LC_TIME") || Quickshell.env("LANG") || "C").split(".")[0])
    readonly property string language: locale.name.split("_")[0]
    property real now: Date.now()

    Timer {
        interval: popup.shown ? 1000 : 60000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: world.now = Date.now()
    }

    // the cities: [{name, region, tz, lat, lon, people}]
    FileView {
        id: store

        path: Quickshell.statePath("worldclock.json")
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound)
                writeAdapter()
        }

        JsonAdapter {
            id: saved

            property var cities: []
        }
    }
    readonly property var cities: saved.cities

    function save(list) {
        saved.cities = list
        store.writeAdapter()
        readZones.running = false
        readZones.running = true
        weather.fetched = 0
        weather.fetch()
    }
    function add(place) {
        if (cities.some(c => c.tz === place.timezone && c.name === place.name))
            return
        save(cities.concat([{ name: place.name, region: [place.admin1, place.country].filter(x => x).join(", "), tz: place.timezone, lat: place.latitude, lon: place.longitude, people: "" }]))
    }
    function remove(i) {
        save(cities.filter((c, j) => j !== i))
    }
    function setPeople(i, text) {
        save(cities.map((c, j) => j === i ? Object.assign({}, c, { people: text.trim() }) : c))
    }

    // here: the system's zone, its city
    property string homeZone: ""
    Process {
        running: true
        command: ["timedatectl", "show", "-p", "Timezone", "--value"]
        stdout: StdioCollector {
            onStreamFinished: {
                world.homeZone = text.trim()
                readZones.running = true
            }
        }
    }
    readonly property string homeCity: homeZone.split("/").pop().replace(/_/g, " ")

    // each zone's offset (minutes) and abbreviation, from the system's tzdata
    property var zones: ({})
    Process {
        id: readZones

        command: ["sh", "-c", 'for z do printf "%s %s %s\\n" "$z" "$(TZ="$z" date +%z)" "$(TZ="$z" date +%Z)"; done', "sh"].concat([world.homeZone].concat(world.cities.map(c => c.tz)).filter(z => z))
        stdout: StdioCollector {
            onStreamFinished: {
                const out = {}
                for (const line of text.trim().split("\n")) {
                    const [z, off, abbr] = line.split(" ")
                    if (!z || !off)
                        continue
                    const sign = off[0] === "-" ? -1 : 1
                    out[z] = { offset: sign * (parseInt(off.slice(1, 3)) * 60 + parseInt(off.slice(3, 5))), abbr: abbr || "" }
                }
                world.zones = out
            }
        }
    }
    Timer {
        interval: 600000
        running: true
        repeat: true
        onTriggered: readZones.running = true
    }

    // the weather and the sun, a city at a time in one request
    QtObject {
        id: weather

        property var byCity: ({}) // "lat,lon": {temp, code, day, sunrise, sunset}
        property real fetched: 0

        function fetch() {
            if (world.cities.length === 0 || Date.now() - fetched < 30 * 60000)
                return
            fetched = Date.now()
            const lat = world.cities.map(c => c.lat.toFixed(3)).join(",")
            const lon = world.cities.map(c => c.lon.toFixed(3)).join(",")
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE)
                    return
                if (xhr.status !== 200) {
                    fetched = 0
                    return
                }
                try {
                    let answer = JSON.parse(xhr.responseText)
                    if (!Array.isArray(answer))
                        answer = [answer]
                    const out = {}
                    world.cities.forEach((c, i) => {
                        const a = answer[i]
                        if (!a || !a.current)
                            return
                        out[`${c.lat},${c.lon}`] = {
                            temp: Math.round(a.current.temperature_2m),
                            code: a.current.weather_code,
                            day: a.current.is_day === 1,
                            sunrise: a.daily && a.daily.sunrise ? a.daily.sunrise[0] : "",
                            sunset: a.daily && a.daily.sunset ? a.daily.sunset[0] : ""
                        }
                    })
                    byCity = out
                } catch (e) {}
            }
            xhr.open("GET", `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}&current=temperature_2m,weather_code,is_day&daily=sunrise,sunset&timezone=auto&forecast_days=1`)
            xhr.send()
        }
    }

    // WMO weather codes, as Lucide draws them
    function weatherIcon(code, day) {
        if (code === 0)
            return day ? "sun" : "moon"
        if (code <= 2)
            return day ? "cloud-sun" : "cloud-moon"
        if (code === 3)
            return "cloud"
        if (code === 45 || code === 48)
            return "cloud-fog"
        if (code >= 51 && code <= 57)
            return "cloud-drizzle"
        if (code >= 71 && code <= 77 || code === 85 || code === 86)
            return "cloud-snow"
        if (code >= 95)
            return "cloud-lightning"
        return "cloud-rain"
    }

    // a city's wall clock: a Date whose UTC fields are its local time
    function wall(tz) {
        const z = zones[tz]
        return z ? new Date(now + z.offset * 60000) : null
    }
    function hhmm(d) {
        return `${String(d.getUTCHours()).padStart(2, "0")}:${String(d.getUTCMinutes()).padStart(2, "0")}`
    }
    function diff(tz) {
        const here = zones[homeZone], there = zones[tz]
        if (!here || !there)
            return ""
        const m = there.offset - here.offset
        if (m === 0)
            return "same time"
        const h = Math.floor(Math.abs(m) / 60), mm = Math.abs(m) % 60
        return (m > 0 ? "+" : "−") + h + "h" + (mm ? String(mm).padStart(2, "0") : "")
    }
    function partOfDay(d) {
        const h = d.getUTCHours()
        return h < 5 ? "Night" : h < 12 ? "Morning" : h < 18 ? "Afternoon" : h < 22 ? "Evening" : "Night"
    }
    // "Tomorrow, mer. 18 nov.", or nothing on the same day as here
    function dayWord(d) {
        const here = wall(homeZone)
        if (!here)
            return ""
        const a = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()), b = Date.UTC(here.getUTCFullYear(), here.getUTCMonth(), here.getUTCDate())
        if (a === b)
            return ""
        const local = new Date(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 12)
        return `${a > b ? "Tomorrow" : "Yesterday"}, ${local.toLocaleDateString(locale, "ddd d MMM")}`
    }
    // "2026-11-17T07:45" → the share of the day gone
    function dayShare(iso) {
        const m = /T(\d\d):(\d\d)/.exec(iso || "")
        return m ? (parseInt(m[1]) * 60 + parseInt(m[2])) / 1440 : -1
    }

    // the search: Open-Meteo's places, as typed (a pause first)
    property string query: ""
    property var results: []
    Timer {
        id: searchLater

        interval: 350
        onTriggered: {
            const q = world.query.trim()
            if (q.length < 2) {
                world.results = []
                return
            }
            const xhr = new XMLHttpRequest()
            xhr.onreadystatechange = () => {
                if (xhr.readyState !== XMLHttpRequest.DONE || world.query.trim() !== q)
                    return
                try {
                    world.results = xhr.status === 200 ? (JSON.parse(xhr.responseText).results || []).filter(r => r.timezone) : []
                } catch (e) {
                    world.results = []
                }
            }
            xhr.open("GET", `https://geocoding-api.open-meteo.com/v1/search?name=${encodeURIComponent(q)}&count=6&language=${world.language}&format=json`)
            xhr.send()
        }
    }
    onQueryChanged: searchLater.restart()

    BarPopup {
        id: popup

        bar: world.bar
        from: world
        name: "world"
        popupWidth: 380
        onShownChanged: {
            if (shown) {
                world.now = Date.now()
                readZones.running = true
                weather.fetch()
            } else {
                world.query = ""
            }
        }

        PopupHero {
            iconSource: Qt.resolvedUrl("icons/globe.svg")
            title: "World clock"
            caption: world.homeZone ? `It's ${world.hhmm(world.wall(world.homeZone) ?? new Date())} here in ${world.homeCity}` : ""
        }

        Text {
            visible: world.cities.length === 0
            width: parent.width
            leftPadding: 4
            topPadding: 4
            bottomPadding: 4
            text: "No cities yet: search for one below."
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 12
        }

        Repeater {
            model: world.cities

            Rectangle {
                id: city

                required property var modelData
                required property int index
                readonly property var at: world.wall(modelData.tz)
                readonly property var sky: weather.byCity[`${modelData.lat},${modelData.lon}`] ?? null
                property bool editing: false
                // its buttons take the pointer from the row: still hovered
                readonly property bool hot: hover.containsMouse || peopleButton.hovered || removeButton.hovered

                width: parent.width
                height: 86
                radius: 8
                color: hot || editing ? Theme.slot : "transparent"

                MouseArea {
                    id: hover

                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                // the city, who lives there, the part of its day
                Column {
                    x: 10
                    y: 8
                    width: parent.width - 150
                    spacing: 2

                    Text {
                        width: parent.width
                        text: city.modelData.name
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }

                    Text {
                        visible: !city.editing
                        width: parent.width
                        text: city.modelData.people !== "" ? city.modelData.people : city.hot ? city.modelData.region : ""
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11
                    }

                    TextInput {
                        id: people

                        visible: city.editing
                        width: parent.width
                        color: Theme.text
                        selectionColor: Theme.accent
                        font.family: Theme.font
                        font.pixelSize: 11
                        clip: true
                        onAccepted: {
                            world.setPeople(city.index, text)
                            city.editing = false
                        }
                        Keys.onEscapePressed: city.editing = false

                        Text {
                            visible: people.text === ""
                            text: "Who lives there?"
                            color: Theme.dim
                            font: people.font
                        }
                    }

                    Text {
                        width: parent.width
                        text: city.at ? [world.partOfDay(city.at), world.dayWord(city.at)].filter(x => x).join(" · ") : ""
                        elide: Text.ElideRight
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }

                // its weather; on hover, its people and removal
                Row {
                    anchors.right: time.left
                    anchors.rightMargin: 14
                    y: 10
                    spacing: 4

                    Row {
                        visible: !city.hot && city.sky !== null
                        spacing: 4

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: city.sky ? `${city.sky.temp}°` : ""
                            color: Theme.dim
                            font.family: Theme.font
                            font.pixelSize: 12
                        }
                        Glyph {
                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                            source: city.sky ? Qt.resolvedUrl(`icons/${world.weatherIcon(city.sky.code, city.sky.day)}.svg`) : ""
                            color: Theme.dim
                        }
                    }

                    Chevron {
                        id: peopleButton

                        visible: city.hot
                        width: 26
                        height: 26
                        icon: "users"
                        onClicked: {
                            people.text = city.modelData.people
                            city.editing = true
                            people.forceActiveFocus()
                        }
                    }
                    Chevron {
                        id: removeButton

                        visible: city.hot
                        width: 26
                        height: 26
                        icon: "x"
                        onClicked: world.remove(city.index)
                    }
                }

                // its time, and how far it is from here
                Column {
                    id: time

                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    y: 6
                    spacing: 0

                    Text {
                        anchors.right: parent.right
                        text: city.at ? world.hhmm(city.at) : "--:--"
                        color: Theme.text
                        font.family: Theme.font
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                    }
                    Text {
                        anchors.right: parent.right
                        text: {
                            const z = world.zones[city.modelData.tz]
                            return z ? [z.abbr.match(/^[A-Z]/) ? z.abbr : "", world.diff(city.modelData.tz)].filter(x => x).join(" ") : ""
                        }
                        color: Theme.dim
                        font.family: Theme.font
                        font.pixelSize: 11
                    }
                }

                // its day: the night dim, the daylight lit, now a dot
                Item {
                    id: dayLine

                    readonly property real rise: city.sky ? world.dayShare(city.sky.sunrise) : -1
                    readonly property real set: city.sky ? world.dayShare(city.sky.sunset) : -1
                    readonly property real now: city.at ? (city.at.getUTCHours() * 60 + city.at.getUTCMinutes()) / 1440 : -1

                    x: 10
                    y: parent.height - 16
                    width: parent.width - 20
                    height: 4

                    Rectangle {
                        anchors.fill: parent
                        radius: 2
                        color: Theme.alpha(Theme.textColor, 0.10)
                    }
                    Rectangle {
                        visible: dayLine.rise >= 0 && dayLine.set > dayLine.rise
                        x: parent.width * dayLine.rise
                        width: parent.width * (dayLine.set - dayLine.rise)
                        height: parent.height
                        radius: 2
                        color: Theme.alpha(Theme.textColor, 0.35)
                    }
                    Rectangle {
                        readonly property bool lit: dayLine.rise >= 0 ? dayLine.now >= dayLine.rise && dayLine.now <= dayLine.set : city.at !== null && city.at.getUTCHours() >= 7 && city.at.getUTCHours() < 19

                        visible: dayLine.now >= 0
                        x: parent.width * dayLine.now - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10
                        height: 10
                        radius: 5
                        color: lit ? "#eec05b" : Theme.text
                        border.width: 2
                        border.color: Theme.popup
                    }
                }
            }
        }

        SectionLabel {
            text: "Add a city"
        }

        Rectangle {
            width: parent.width
            height: 34
            radius: 8
            color: Theme.alpha(Theme.textColor, 0.06)
            border.width: 1
            border.color: search.activeFocus ? Theme.accent : Theme.outline

            Glyph {
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                size: 14
                source: Qt.resolvedUrl("icons/search.svg")
                color: Theme.dim
            }

            TextInput {
                id: search

                // typed into as soon as the popup opens
                focus: true

                x: 32
                width: parent.width - 42
                anchors.verticalCenter: parent.verticalCenter
                text: world.query
                onTextChanged: world.query = text
                color: Theme.text
                selectionColor: Theme.accent
                font.family: Theme.font
                font.pixelSize: 13
                clip: true
                onAccepted: {
                    if (world.results.length > 0) {
                        world.add(world.results[0])
                        world.query = ""
                    }
                }

                Text {
                    visible: search.text === ""
                    text: "A town or a city…"
                    color: Theme.dim
                    font: search.font
                }
            }
        }

        Repeater {
            model: world.results

            ListRow {
                required property var modelData

                lineIcon: Qt.resolvedUrl("icons/plus.svg")
                title: modelData.name
                subtitle: [modelData.admin1, modelData.country].filter(x => x).join(", ")
                trailing: modelData.timezone
                onClicked: {
                    world.add(modelData)
                    world.query = ""
                }
            }
        }
    }
}
