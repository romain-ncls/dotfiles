package main

import "fmt"

// The Plasma controls: what Plasma's own components (in panel popups,
// Kickoff, the tray) draw from the theme. The application style's rules
// (style.css), on popups' lighter surface: buttons are a wash of the text
// color, text fields a darker field with a faint ring that brightens on
// hover, flat things light up with the hover wash, what is on or selected
// takes the accent; the accent ring is for keyboard focus and a focused
// text field. Breeze's element names and sizes, so Plasma lays everything
// out as before.

const (
	text      = "ColorScheme-Text"
	accent    = "ColorScheme-Highlight"
	onAccent  = "ColorScheme-HighlightedText"
	field     = "ColorScheme-ViewBackground"
	ringOp    = 0.12 // the mockup's border: text at 12%
	ringHover = 0.28 // its stronger border
	pressWash = 0.11
	ctlRadius = 6
)

// frames writes several highlight frames side by side, each with its
// content margins, and returns the document's size.
type frameSpec struct {
	prefix string // with its trailing "-", or "" for a plain frame
	look   look
	margin float64 // content margins (0: none written, the slices' size)
}

func frames(d *svgDoc, ox float64, r float64, specs []frameSpec) (w, h float64) {
	for _, s := range specs {
		fw, fh := highlight(d, ox, s.prefix, r, s.look, "")
		if s.margin > 0 {
			hints(d, s.prefix, s.margin)
		}
		ox += fw + 4
		h = max(h, fh)
	}
	return ox, h
}

// element is a single SVG element of a fixed size (not a frame), at (x, 0):
// a transparent box keeps its size, then the drawing.
func element(d *svgDoc, x float64, id string, w, h float64, drawing string) float64 {
	d.add(`<g id="%s"><rect fill="#000" fill-opacity="0" x="%g" y="0" width="%g" height="%g"/>%s</g>`, id, x, w, h, drawing)
	return x + w + 4
}

func circle(class string, op, cx, cy, r float64) string {
	return fmt.Sprintf(`<circle %s cx="%g" cy="%g" r="%g"/>`, fill(class, op), cx, cy, r)
}

func ringCircle(class string, op, cx, cy, r float64) string {
	return fmt.Sprintf(`<circle class="%s" fill="none" stroke="currentColor" stroke-width="1" opacity="%g" cx="%g" cy="%g" r="%g"/>`, class, op, cx, cy, r-0.5)
}

func line(class string, op, width float64, d string) string {
	return fmt.Sprintf(`<path class="%s" fill="none" stroke="currentColor" stroke-width="%g" stroke-linecap="round" stroke-linejoin="round" opacity="%g" d="%s"/>`, class, width, op, d)
}

func tileHint(d *svgDoc) {
	d.add(`<rect id="hint-tile-center" x="0" y="0" width="5" height="5" fill="#f60"/>`)
}

// buttonSVG: buttons, tool buttons, drop-downs and the check box's box.
// Popups are lighter than the raised color, so buttons there are a wash of
// the text color (the mockup's notification buttons), stronger on hover.
// "focus" is drawn over the others for keyboard focus.
func buttonSVG() string {
	var d svgDoc
	w, h := frames(&d, 0, ctlRadius, []frameSpec{
		{"normal-", look{bg: text, bgOp: hoverWash}, 6},
		{"hover-", look{bg: text, bgOp: pressWash}, 6},
		{"pressed-", look{bg: text, bgOp: 0.16}, 6},
		{"focus-", look{ring: 1, ringClass: accent}, 6},
		{"toolbutton-hover-", look{bg: text, bgOp: hoverWash}, 4},
		{"toolbutton-pressed-", look{bg: text, bgOp: pressWash}, 4},
		{"toolbutton-focus-", look{ring: 1, ringClass: accent}, 4},
	})
	tileHint(&d)
	return d.String(w, h, "")
}

// lineeditSVG: text fields; "hover" and "focus" are drawn over "base".
func lineeditSVG() string {
	var d svgDoc
	w, h := frames(&d, 0, ctlRadius, []frameSpec{
		{"base-", look{bg: field, bgOp: 1, ring: ringOp, ringClass: text}, 6},
		{"hover-", look{ring: ringHover, ringClass: text}, 0},
		{"focus-", look{ring: 1, ringClass: accent}, 0},
	})
	// TextFieldFocus grows these two frames by their margins (by default
	// the corners); 1 px puts the ring on the field's edge (an empty hint
	// counts as none).
	hints(&d, "hover-", 1)
	hints(&d, "focus-", 1)
	d.add(`<rect id="hint-focus-over-base" x="0" y="0" width="2" height="2" fill="#f0f"/>`)
	tileHint(&d)
	return d.String(w, h, "")
}

// listitemSVG: rows in popups (network, notifications history, clipboard).
func listitemSVG() string {
	var d svgDoc
	w, h := frames(&d, 0, ctlRadius, []frameSpec{
		{"normal-", look{}, 6},
		{"hover-", look{bg: text, bgOp: hoverWash}, 6},
		{"pressed-", look{bg: accent, bgOp: selTint}, 6},
		{"section-", look{}, 6},
	})
	element(&d, w, "separator", tile, 1, fmt.Sprintf(`<rect %s x="%g" y="0" width="%d" height="1"/>`, fill(text, hoverWash), w, tile))
	tileHint(&d)
	return d.String(w+tile+4, h, "")
}

// menubaritemSVG: the application menu and window list in the panel.
func menubaritemSVG() string {
	var d svgDoc
	w, h := frames(&d, 0, ctlRadius, []frameSpec{
		{"normal-", look{}, 8},
		{"hover-", look{bg: text, bgOp: hoverWash}, 8},
		{"pressed-", look{bg: text, bgOp: pressWash}, 8},
	})
	tileHint(&d)
	return d.String(w, h, "")
}

// frameSVG: PlasmaComponents Frame (only "plain" is still used).
func plainFrameSVG() string {
	var d svgDoc
	w, h := frames(&d, 0, ctlRadius, []frameSpec{{"plain-", look{ring: hoverWash, ringClass: text}, 6}})
	tileHint(&d)
	return d.String(w, h, "")
}

// toolbarSVG: PlasmaComponents ToolBar: nothing drawn, the popup shows.
func toolbarSVG() string {
	var d svgDoc
	w, h := frames(&d, 0, ctlRadius, []frameSpec{{"", look{}, 4}})
	tileHint(&d)
	return d.String(w, h, "")
}

// lineSVG: separators, the mockup's 7% line.
func lineSVG() string {
	var d svgDoc
	x := element(&d, 0, "horizontal-line", tile, 1, fmt.Sprintf(`<rect %s x="0" y="0" width="%d" height="1"/>`, fill(text, 0.10), tile))
	x = element(&d, x, "vertical-line", 1, tile, fmt.Sprintf(`<rect %s x="%g" y="0" width="1" height="%d"/>`, fill(text, 0.10), x, tile))
	return d.String(x, tile, "")
}

// scrollbarSVG: thin pill, no track, as the application style.
func scrollbarSVG() string {
	var d svgDoc
	const r = 3
	w, h := frames(&d, 0, r, []frameSpec{
		{"slider-", look{bg: text, bgOp: 0.28}, 0},
		{"mouseover-slider-", look{bg: text, bgOp: 0.45}, 0},
		{"background-vertical-", look{}, 0},
		{"background-horizontal-", look{}, 0},
	})
	d.add(`<rect id="hint-scrollbar-size" x="0" y="0" width="6" height="6" fill="#f0f"/>`)
	tileHint(&d)
	return d.String(w, h, "")
}

// sliderSVG: volume and brightness: a track, the accent up to the handle,
// a light round handle (the mockup's knob).
func sliderSVG() string {
	var d svgDoc
	const r = 2
	w, h := frames(&d, 0, r, []frameSpec{
		{"groove-", look{bg: text, bgOp: 0.14}, 0},
		{"groove-highlight-", look{bg: accent, bgOp: 1}, 0},
	})
	x := w
	knob := func(extra string) string {
		return circle("ColorScheme-Background", 0.35, 10, 10.5, 8.5) + circle(text, 1, 10, 10, 8) + extra
	}
	for _, o := range []string{"horizontal", "vertical"} {
		x = element(&d, x, o+"-slider-handle", 20, 20, shift(x, knob("")))
		x = element(&d, x, o+"-slider-hover", 20, 20, shift(x, knob(ringCircle(accent, 0.6, 10, 10, 9))))
		x = element(&d, x, o+"-slider-focus", 20, 20, shift(x, ringCircle(accent, 1, 10, 10, 10)))
		x = element(&d, x, o+"-slider-shadow", 20, 20, "")
	}
	d.add(`<rect id="hint-handle-size" x="0" y="0" width="20" height="20" fill="#f0f"/>`)
	tileHint(&d)
	return d.String(x, max(h, 20), "")
}

// shift moves a drawing made at the origin to x.
func shift(x float64, drawing string) string {
	return fmt.Sprintf(`<g transform="translate(%g 0)">%s</g>`, x, drawing)
}

// switchSVG: the mockup's switch: a 36×20 pill, accent when on, a 14 px
// handle inside it.
func switchSVG() string {
	var d svgDoc
	const r = 10
	w, h := frames(&d, 0, r, []frameSpec{
		{"inactive-", look{bg: text, bgOp: 0.14, ring: ringOp, ringClass: text}, 0},
		{"active-", look{bg: accent, bgOp: 1}, 0},
	})
	x := w
	x = element(&d, x, "handle", 20, 20, shift(x, circle(text, 1, 10, 10, 7)))
	x = element(&d, x, "handle-hover", 20, 20, shift(x, circle(text, 1, 10, 10, 7.5)))
	x = element(&d, x, "handle-pressed", 20, 20, shift(x, circle(text, 1, 10, 10, 7)))
	x = element(&d, x, "handle-focus", 20, 20, shift(x, ringCircle(accent, 1, 10, 10, 10)))
	x = element(&d, x, "handle-shadow", 20, 20, "")
	d.add(`<rect id="hint-bar-size" x="0" y="0" width="36" height="20" fill="#f0f"/>`)
	d.add(`<rect id="hint-stretch-borders" x="0" y="0" width="4" height="4" fill="#f0f"/>`)
	return d.String(x, max(h, 20), "")
}

// checkmarksSVG: the checked box (drawn over the button frame) and the dot.
func checkmarksSVG() string {
	var d svgDoc
	box := fmt.Sprintf(`<rect %s x="0" y="0" width="16" height="16" rx="4"/>`, fill(accent, 1)) +
		line(onAccent, 1, 2, "M4.5,8.5 L7,11 L11.5,5.5")
	x := element(&d, 0, "checkbox", 16, 16, box)
	x = element(&d, x, "radiobutton", 16, 16, shift(x, circle(accent, 1, 8, 8, 8)+circle(onAccent, 1, 8, 8, 3)))
	return d.String(x, 16, "")
}

// radiobuttonSVG: PlasmaComponents RadioButton's layers.
func radiobuttonSVG() string {
	var d svgDoc
	x := element(&d, 0, "normal", 16, 16, circle(field, 1, 8, 8, 8)+ringCircle(text, ringHover, 8, 8, 8))
	x = element(&d, x, "hover", 16, 16, shift(x, ringCircle(text, 0.45, 8, 8, 8)))
	x = element(&d, x, "checked", 16, 16, shift(x, circle(accent, 1, 8, 8, 8)))
	x = element(&d, x, "focus", 20, 20, shift(x, ringCircle(accent, 1, 10, 10, 10)))
	x = element(&d, x, "symbol", 6, 6, shift(x, circle(onAccent, 1, 3, 3, 3)))
	x = element(&d, x, "shadow", 16, 16, "")
	d.add(`<rect id="hint-size" x="0" y="0" width="16" height="16" fill="#f0f"/>`)
	return d.String(x, 20, "")
}

// arrowsSVG: chevrons, as the Lucide icons.
func arrowsSVG() string {
	var d svgDoc
	x := 0.0
	for _, a := range []struct{ id, path string }{
		{"down-arrow", "M4,6 L8,10 L12,6"},
		{"up-arrow", "M4,10 L8,6 L12,10"},
		{"left-arrow", "M10,4 L6,8 L10,12"},
		{"right-arrow", "M6,4 L10,8 L6,12"},
	} {
		x = element(&d, x, a.id, 16, 16, shift(x, line(text, 1, 1.5, a.path)))
	}
	return d.String(x, 16, "")
}

// barMeterSVG: progress bars (battery, transfers): accent on a 14% track.
func barMeterSVG() string {
	var d svgDoc
	const r = 3
	w, h := frames(&d, 0, r, []frameSpec{
		{"bar-inactive-", look{bg: text, bgOp: 0.14}, 0},
		{"bar-active-", look{bg: accent, bgOp: 1}, 0},
	})
	d.add(`<rect id="hint-bar-size" x="0" y="0" width="6" height="6" fill="#f0f"/>`)
	tileHint(&d)
	return d.String(w, h, "")
}

// busywidgetSVG: an accent arc on a faint ring; Plasma spins it.
func busywidgetSVG() string {
	var d svgDoc
	arc := fmt.Sprintf(`<circle class="%s" fill="none" stroke="currentColor" stroke-width="3" opacity="0.14" cx="18" cy="18" r="14"/>`, text) +
		line(accent, 1, 3, "M18,4 A14,14 0 0 1 32,18")
	x := element(&d, 0, "busywidget", 36, 36, arc)
	return d.String(x, 36, "")
}
