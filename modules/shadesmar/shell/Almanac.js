// The French almanac, as the post office's calendar prints it: each day's
// saint (the name to wish a happy name day to), the public holidays
// (jours fériés, metropolitan France), the feasts that move with Easter or
// with the Sundays (Mardi gras, Fête des mères…), the seasons (the
// equinoxes and solstices, Meeus's method) and the clock's changes (from
// the system's time zone). Computed per year, kept once computed.
//
// The saints: the post office's list, checked against a 2026 calendar
// (January to June, and the first nine days of each other month) and two
// published lists (Mubelotix/calendrier's ephemeris.json, Calendarium's
// namedays/fr.json) where they agree; a feast that moves (Pâques, the
// Rameaux) is printed over its day's saint, as on the calendar.
.pragma library

var SAINTS = {
    "01-01": "Jour de l'An", "01-02": "Basile", "01-03": "Geneviève", "01-04": "Odilon", "01-05": "Édouard",
    "01-06": "Mélaine", "01-07": "Raymond", "01-08": "Lucien", "01-09": "Alix", "01-10": "Guillaume",
    "01-11": "Paulin", "01-12": "Tatiana", "01-13": "Yvette", "01-14": "Nina", "01-15": "Rémi",
    "01-16": "Marcel", "01-17": "Roseline", "01-18": "Prisca", "01-19": "Marius", "01-20": "Sébastien",
    "01-21": "Agnès", "01-22": "Vincent", "01-23": "Barnard", "01-24": "François de Sales", "01-25": "Conv. de St Paul",
    "01-26": "Paule", "01-27": "Angèle", "01-28": "Thomas d'Aquin", "01-29": "Gildas", "01-30": "Martine",
    "01-31": "Marcelle",
    "02-01": "Ella", "02-02": "Chandeleur", "02-03": "Blaise", "02-04": "Véronique", "02-05": "Agathe",
    "02-06": "Gaston", "02-07": "Eugénie", "02-08": "Jacqueline", "02-09": "Apolline", "02-10": "Arnaud",
    "02-11": "N.-D. de Lourdes", "02-12": "Félix", "02-13": "Béatrice", "02-14": "Valentin", "02-15": "Claude",
    "02-16": "Julienne", "02-17": "Alexis", "02-18": "Bernadette", "02-19": "Gabin", "02-20": "Aimée",
    "02-21": "Pierre Damien", "02-22": "Isabelle", "02-23": "Lazare", "02-24": "Modeste", "02-25": "Roméo",
    "02-26": "Nestor", "02-27": "Honorine", "02-28": "Romain", "02-29": "Auguste",
    "03-01": "Aubin", "03-02": "Charles le Bon", "03-03": "Guénolé", "03-04": "Casimir", "03-05": "Olive / Olivia",
    "03-06": "Colette", "03-07": "Félicité", "03-08": "Jean de Dieu", "03-09": "Françoise", "03-10": "Vivien",
    "03-11": "Rosine", "03-12": "Justine", "03-13": "Rodrigue", "03-14": "Mathilde", "03-15": "Louise",
    "03-16": "Bénédicte", "03-17": "Patrick / Patrice", "03-18": "Cyrille", "03-19": "Joseph", "03-20": "Herbert",
    "03-21": "Clémence", "03-22": "Léa", "03-23": "Victorien", "03-24": "Cath. de Suède", "03-25": "Annonciation",
    "03-26": "Larissa", "03-27": "Habib", "03-28": "Gontran", "03-29": "Gwladys", "03-30": "Amédée",
    "03-31": "Benjamin",
    "04-01": "Hugues", "04-02": "Sandrine", "04-03": "Richard", "04-04": "Isidore", "04-05": "Irène",
    "04-06": "Marcellin", "04-07": "J.-B. de la Salle", "04-08": "Julie", "04-09": "Gautier", "04-10": "Fulbert",
    "04-11": "Stanislas", "04-12": "Jules", "04-13": "Ida", "04-14": "Maxime", "04-15": "Paterne",
    "04-16": "Benoît-Joseph", "04-17": "Anicet", "04-18": "Parfait", "04-19": "Emma", "04-20": "Odette",
    "04-21": "Anselme", "04-22": "Alexandre", "04-23": "Georges", "04-24": "Fidèle", "04-25": "Marc",
    "04-26": "Alida", "04-27": "Zita", "04-28": "Valérie", "04-29": "Cath. de Sienne", "04-30": "Robert",
    "05-01": "Fête du Travail", "05-02": "Boris", "05-03": "Philippe / Jacques", "05-04": "Sylvain", "05-05": "Judith",
    "05-06": "Prudence", "05-07": "Gisèle", "05-08": "Victoire 1945", "05-09": "Pacôme", "05-10": "Solange",
    "05-11": "Estelle", "05-12": "Achille", "05-13": "Rolande", "05-14": "Matthias", "05-15": "Denise",
    "05-16": "Honoré", "05-17": "Pascal", "05-18": "Éric", "05-19": "Yves", "05-20": "Bernardin",
    "05-21": "Constantin", "05-22": "Émile", "05-23": "Didier", "05-24": "Donatien", "05-25": "Sophie",
    "05-26": "Bérenger", "05-27": "Augustin de C.", "05-28": "Germain", "05-29": "Aymar", "05-30": "Ferdinand",
    "05-31": "Visitation",
    "06-01": "Justin", "06-02": "Blandine", "06-03": "Kévin", "06-04": "Clotilde", "06-05": "Igor",
    "06-06": "Norbert", "06-07": "Gilbert", "06-08": "Médard", "06-09": "Diane", "06-10": "Landry",
    "06-11": "Barnabé", "06-12": "Guy", "06-13": "Antoine de Padoue", "06-14": "Élisée", "06-15": "Germaine",
    "06-16": "J.-F. Régis", "06-17": "Hervé", "06-18": "Léonce", "06-19": "Romuald", "06-20": "Silvère",
    "06-21": "Rodolphe", "06-22": "Alban", "06-23": "Audrey", "06-24": "Jean-Baptiste", "06-25": "Éléonore / Prosper",
    "06-26": "Anthelme", "06-27": "Fernand", "06-28": "Irénée", "06-29": "Pierre / Paul", "06-30": "Martial",
    "07-01": "Thierry", "07-02": "Martinien", "07-03": "Thomas", "07-04": "Florent", "07-05": "Antoine",
    "07-06": "Mariette", "07-07": "Raoul", "07-08": "Thibaut", "07-09": "Amandine", "07-10": "Ulrich",
    "07-11": "Benoît", "07-12": "Olivier", "07-13": "Henri / Joël", "07-14": "Fête nationale", "07-15": "Donald",
    "07-16": "N.-D. du Mt Carmel", "07-17": "Charlotte", "07-18": "Frédéric", "07-19": "Arsène", "07-20": "Marina",
    "07-21": "Victor", "07-22": "Marie-Madeleine", "07-23": "Brigitte", "07-24": "Christine", "07-25": "Jacques",
    "07-26": "Anne / Joachim", "07-27": "Nathalie", "07-28": "Samson", "07-29": "Marthe", "07-30": "Juliette",
    "07-31": "Ignace de Loyola",
    "08-01": "Alphonse", "08-02": "Julien Eymard", "08-03": "Lydie", "08-04": "J.-M. Vianney", "08-05": "Abel",
    "08-06": "Transfiguration", "08-07": "Gaëtan", "08-08": "Dominique", "08-09": "Amour", "08-10": "Laurent",
    "08-11": "Claire", "08-12": "Clarisse", "08-13": "Hippolyte", "08-14": "Evrard", "08-15": "Assomption",
    "08-16": "Armel", "08-17": "Hyacinthe", "08-18": "Hélène", "08-19": "Jean Eudes", "08-20": "Bernard",
    "08-21": "Christophe", "08-22": "Fabrice", "08-23": "Rose de Lima", "08-24": "Barthélemy", "08-25": "Louis",
    "08-26": "Natacha", "08-27": "Monique", "08-28": "Augustin", "08-29": "Sabine", "08-30": "Fiacre",
    "08-31": "Aristide",
    "09-01": "Gilles", "09-02": "Ingrid", "09-03": "Grégoire", "09-04": "Rosalie", "09-05": "Raïssa",
    "09-06": "Bertrand", "09-07": "Reine", "09-08": "Nativité N.-D.", "09-09": "Alain", "09-10": "Inès",
    "09-11": "Adelphe", "09-12": "Apollinaire", "09-13": "Aimé", "09-14": "La Croix Glorieuse", "09-15": "Roland",
    "09-16": "Édith", "09-17": "Renaud", "09-18": "Nadège", "09-19": "Émilie", "09-20": "Davy",
    "09-21": "Matthieu", "09-22": "Maurice", "09-23": "Constant", "09-24": "Thècle", "09-25": "Hermann",
    "09-26": "Côme / Damien", "09-27": "Vincent de Paul", "09-28": "Venceslas", "09-29": "Michel / Gabriel / Raphaël", "09-30": "Jérôme",
    "10-01": "Thé. de l'E.-Jésus", "10-02": "Léger", "10-03": "Gérard", "10-04": "François d'Assise", "10-05": "Fleur",
    "10-06": "Bruno", "10-07": "Serge", "10-08": "Pélagie", "10-09": "Denis", "10-10": "Ghislain",
    "10-11": "Firmin", "10-12": "Wilfried", "10-13": "Géraud", "10-14": "Juste", "10-15": "Thérèse d'Avila",
    "10-16": "Edwige", "10-17": "Baudouin", "10-18": "Luc", "10-19": "René", "10-20": "Adeline",
    "10-21": "Céline", "10-22": "Élodie", "10-23": "Jean de Capistran", "10-24": "Florentin", "10-25": "Crépin",
    "10-26": "Dimitri", "10-27": "Émeline", "10-28": "Simon / Jude", "10-29": "Narcisse", "10-30": "Bienvenue",
    "10-31": "Quentin",
    "11-01": "Toussaint", "11-02": "Défunts", "11-03": "Hubert", "11-04": "Charles", "11-05": "Sylvie",
    "11-06": "Léonard / Bertille", "11-07": "Carine", "11-08": "Geoffroy", "11-09": "Théodore", "11-10": "Léon",
    "11-11": "Armistice 1918", "11-12": "Christian", "11-13": "Brice", "11-14": "Sidoine", "11-15": "Albert",
    "11-16": "Marguerite", "11-17": "Élisabeth", "11-18": "Aude", "11-19": "Tanguy", "11-20": "Edmond",
    "11-21": "Prés. de Marie", "11-22": "Cécile", "11-23": "Clément", "11-24": "Flora", "11-25": "Catherine",
    "11-26": "Delphine", "11-27": "Sévrin", "11-28": "Jacques de la Marche", "11-29": "Saturnin", "11-30": "André",
    "12-01": "Florence", "12-02": "Viviane", "12-03": "François-Xavier", "12-04": "Barbara", "12-05": "Gérald",
    "12-06": "Nicolas", "12-07": "Ambroise", "12-08": "Immac. Conception", "12-09": "Pierre Fourier", "12-10": "Romaric",
    "12-11": "Daniel", "12-12": "Jeanne-F. de Chantal", "12-13": "Lucie", "12-14": "Odile", "12-15": "Ninon",
    "12-16": "Alice", "12-17": "Gaël", "12-18": "Gatien", "12-19": "Urbain", "12-20": "Théophile",
    "12-21": "Pierre Canisius", "12-22": "Françoise-Xavière", "12-23": "Armand", "12-24": "Adèle", "12-25": "Noël",
    "12-26": "Étienne", "12-27": "Jean", "12-28": "Innocents", "12-29": "David", "12-30": "Roger",
    "12-31": "Sylvestre"
}

// fixed days the calendar prints in bold, as feasts
var FEASTS = ["02-02", "02-14", "03-25", "08-06", "12-08"]

function pad(n) {
    return (n < 10 ? "0" : "") + n
}
function key(d) {
    return pad(d.getMonth() + 1) + "-" + pad(d.getDate())
}
// local noon: a day whatever the clock's changes
function day(y, m, d) {
    return new Date(y, m, d, 12)
}
function plus(d, n) {
    return day(d.getFullYear(), d.getMonth(), d.getDate() + n)
}

function saint(d) {
    return SAINTS[key(d)] || ""
}

// Easter Sunday (the Gregorian computus, Meeus/Jones/Butcher)
function easter(y) {
    var a = y % 19, b = Math.floor(y / 100), c = y % 100
    var d = Math.floor(b / 4), e = b % 4, f = Math.floor((b + 8) / 25)
    var g = Math.floor((b - f + 1) / 3), h = (19 * a + b - d - g + 15) % 30
    var i = Math.floor(c / 4), k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
    var m = Math.floor((a + 11 * h + 22 * l) / 451)
    var month = Math.floor((h + l - 7 * m + 114) / 31), date = (h + l - 7 * m + 114) % 31 + 1
    return day(y, month - 1, date)
}

// the n-th (1…) or last (-1) Sunday of a month
function sunday(y, m, n) {
    if (n > 0) {
        var first = day(y, m, 1)
        return plus(first, (7 - first.getDay()) % 7 + 7 * (n - 1))
    }
    var last = day(y, m + 1, 0)
    return plus(last, -last.getDay())
}

// Meeus, Astronomical Algorithms, ch. 27: the instant of the March
// equinox (0), June solstice (1), September equinox (2), December
// solstice (3), as a Date (ΔT taken as 69 s).
var SEASON_TERMS = [
    [485, 324.96, 1934.136], [203, 337.23, 32964.467], [199, 342.08, 20.186], [182, 27.85, 445267.112],
    [156, 73.14, 45036.886], [136, 171.52, 22518.443], [77, 222.54, 65928.934], [74, 296.72, 3034.906],
    [70, 243.58, 9037.513], [58, 119.81, 33718.147], [52, 297.17, 150.678], [50, 21.02, 2281.226],
    [45, 247.54, 29929.562], [44, 325.15, 31555.956], [29, 60.93, 4443.417], [18, 155.12, 67555.328],
    [17, 288.79, 4562.452], [16, 198.04, 62894.029], [14, 199.76, 31436.921], [12, 95.39, 14577.848],
    [12, 287.11, 31931.756], [12, 320.81, 34777.259], [9, 227.73, 1222.114], [8, 15.45, 16859.074]
]
var SEASON_MEAN = [
    [2451623.80984, 365242.37404, 0.05169, -0.00411, -0.00057],
    [2451716.56767, 365241.62603, 0.00325, 0.00888, -0.00030],
    [2451810.21715, 365242.01767, -0.11575, 0.00337, 0.00078],
    [2451900.05952, 365242.74049, -0.06223, -0.00823, 0.00032]
]
function season(y, which) {
    var c = SEASON_MEAN[which], Y = (y - 2000) / 1000
    var jde0 = c[0] + c[1] * Y + c[2] * Y * Y + c[3] * Y * Y * Y + c[4] * Y * Y * Y * Y
    var T = (jde0 - 2451545.0) / 36525
    var rad = Math.PI / 180
    var W = (35999.373 * T - 2.47) * rad
    var dl = 1 + 0.0334 * Math.cos(W) + 0.0007 * Math.cos(2 * W)
    var S = 0
    for (var i = 0; i < SEASON_TERMS.length; i++) {
        var t = SEASON_TERMS[i]
        S += t[0] * Math.cos((t[1] + t[2] * T) * rad)
    }
    var jde = jde0 + 0.00001 * S / dl
    return new Date((jde - 2440587.5) * 86400000 - 69000)
}

// "MM-DD": [{name, kind}], kind: "holiday" (a day off), "feast" (printed
// in bold), "season"; the first one is printed
var cache = {}
function events(y) {
    if (cache[y])
        return cache[y]
    var out = {}
    function add(d, name, kind) {
        var k = key(d)
        if (!out[k])
            out[k] = []
        out[k].push({ name: name, kind: kind })
    }
    var e = easter(y)
    // the days off
    add(day(y, 0, 1), "Jour de l'An", "holiday")
    add(e, "Pâques", "holiday")
    add(plus(e, 1), "Lundi de Pâques", "holiday")
    add(day(y, 4, 1), "Fête du Travail", "holiday")
    add(day(y, 4, 8), "Victoire 1945", "holiday")
    add(plus(e, 39), "Ascension", "holiday")
    add(plus(e, 49), "Pentecôte", "holiday")
    add(plus(e, 50), "Lundi de Pentecôte", "holiday")
    add(day(y, 6, 14), "Fête nationale", "holiday")
    add(day(y, 7, 15), "Assomption", "holiday")
    add(day(y, 10, 1), "Toussaint", "holiday")
    add(day(y, 10, 11), "Armistice 1918", "holiday")
    add(day(y, 11, 25), "Noël", "holiday")
    // the feasts that move
    add(sunday(y, 0, 1).getDate() === 1 ? sunday(y, 0, 2) : sunday(y, 0, 1), "Épiphanie", "feast")
    add(plus(e, -47), "Mardi gras", "feast")
    add(plus(e, -46), "Carême", "feast")
    add(plus(e, -24), "Mi-Carême", "feast")
    add(plus(e, -7), "Rameaux", "feast")
    add(plus(e, -2), "Vendredi saint", "feast")
    add(sunday(y, 2, 1), "Fête des grands-mères", "feast")
    add(sunday(y, 3, -1), "Souvenir des déportés", "feast")
    var mothers = sunday(y, 4, -1)
    if (key(mothers) === key(plus(e, 49)))
        mothers = sunday(y, 5, 1)
    add(mothers, "Fête des mères", "feast")
    add(sunday(y, 5, 3), "Fête des pères", "feast")
    add(sunday(y, 9, 1), "Fête des grands-pères", "feast")
    var names = ["Printemps", "Été", "Automne", "Hiver"]
    for (var s = 0; s < 4; s++) {
        var at = season(y, s)
        add(day(at.getFullYear(), at.getMonth(), at.getDate()), names[s], "season")
    }
    // the first printed: a day off, then a feast, then a season
    var rank = { holiday: 0, feast: 1, season: 2 }
    for (var k in out)
        out[k].sort(function (a, b) { return rank[a.kind] - rank[b.kind] })
    cache[y] = out
    return out
}

// what the calendar prints for a day: {name, kind ("holiday", "feast",
// "season", "" for the saint), also: the other events}
function label(d) {
    var list = events(d.getFullYear())[key(d)] || []
    if (list.length > 0)
        return { name: list[0].name, kind: list[0].kind, also: list.slice(1).map(function (x) { return x.name }), saint: saint(d) }
    var k = key(d)
    return { name: saint(d), kind: FEASTS.indexOf(k) >= 0 ? "feast" : "", also: [], saint: saint(d) }
}

function holiday(d) {
    var list = events(d.getFullYear())[key(d)] || []
    return list.length > 0 && list[0].kind === "holiday"
}

// the clock's change on that day, from the system's time zone: "+1h",
// "−1h", or ""
function clockChange(d) {
    var before = day(d.getFullYear(), d.getMonth(), d.getDate() - 1).getTimezoneOffset()
    var after = d.getTimezoneOffset()
    if (after === before)
        return ""
    var h = (before - after) / 60
    return (h > 0 ? "+" : "−") + Math.abs(h) + "h"
}

// ISO 8601: the week of its Thursday
function isoWeek(d) {
    var t = day(d.getFullYear(), d.getMonth(), d.getDate() - (d.getDay() + 6) % 7 + 3)
    var jan4 = day(t.getFullYear(), 0, 4)
    var thu1 = day(t.getFullYear(), 0, 4 - (jan4.getDay() + 6) % 7 + 3)
    return 1 + Math.round((t - thu1) / (7 * 86400000))
}
