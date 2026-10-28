package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// The Plasma style ("desktop theme"): panel, popups and tooltips. Plasma
// draws them as 9-slice SVG frames; we generate those from a few numbers so
// radius and glass stay consistent. Colors come from the color scheme (the
// ColorScheme-* classes), so they follow the palette live. Every SVG this
// theme leaves out (buttons, sliders, highlights…) falls back to Breeze.

// frame is one frame SVG.
type frame struct {
	radius  float64 // corner radius, also the size of the border slices
	opacity float64 // fill opacity of the background
	margin  float64 // content padding
	shadow  float64 // shadow reach outside the frame; 0 = none
	depth   float64 // shadow opacity at the frame's edge
	outline bool    // a 1 px hairline around the frame, as on windows
}

// The "glass": what is under a panel or popup shows through, blurred by KWin.
const glass = 0.80

var (
	popup   = frame{radius: 10, opacity: glass, margin: 6, shadow: 16, depth: 0.35, outline: true}
	tooltip = frame{radius: 6, opacity: glass, margin: 4, shadow: 10, depth: 0.30, outline: true}
	panel   = frame{radius: 10, opacity: glass, margin: 2, shadow: 10, depth: 0.25, outline: true}
)

// Plasma picks a variant folder: translucent/ when KWin blurs behind (the
// only glass one: unblurred, 80% is hard to read), the base one when it
// composites without blur, opaque/ without compositing,
// solid/ for a panel set to opaque (or adaptive, with a maximized window).
var variants = []struct {
	dir    string
	opaque bool
}{{"", true}, {"translucent", false}, {"opaque", true}, {"solid", true}}

func writePlasmaTheme(dir string) error {
	files := map[string]string{
		"metadata.json": plasmaMetadata,
		// Adaptive: a panel goes opaque (solid/) while a window is maximized.
		"plasmarc":                    "[AdaptiveTransparency]\nenabled=true\n",
		"widgets/plasmoidheading.svg": headingSVG(popup.radius),
	}
	for _, v := range variants {
		for name, f := range map[string]frame{
			"dialogs/background.svg":       popup,
			"widgets/tooltip.svg":          tooltip,
			"widgets/panel-background.svg": panel,
		} {
			if v.opaque {
				f.opacity = 1
			}
			files[filepath.Join(v.dir, name)] = frameSVG(f)
		}
	}
	for name, content := range files {
		path := filepath.Join(dir, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			return err
		}
	}
	return nil
}

const plasmaMetadata = `{
    "KPlugin": {
        "Authors": [{ "Name": "Romain Nicolas" }],
        "Description": "Nalthis: dark glass panel and popups, colors from the color scheme",
        "Id": "nalthis",
        "License": "MIT",
        "Name": "Nalthis",
        "Version": "1"
    },
    "X-Plasma-API": "5.0"
}
`

// KSvg replaces this style sheet with the current color scheme's colors.
const colorStyle = `<style id="current-color-scheme" type="text/css">
.ColorScheme-Text { color:#fcfcfc; }
.ColorScheme-Background { color:#202326; }
</style>`

// svgDoc collects elements; Plasma finds each slice by its id and uses its
// bounding box, so every slice's shapes must span exactly its box.
type svgDoc struct{ b strings.Builder }

func (d *svgDoc) add(format string, a ...any) { fmt.Fprintf(&d.b, format+"\n", a...) }

func (d *svgDoc) String(w, h float64, defs string) string {
	return fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="%g" height="%g">
<defs>
%s
%s</defs>
%s</svg>
`, w, h, colorStyle, defs, d.b.String())
}

const tile = 32 // size of the stretched middle slices

// corner is a point helper for one corner: (cx, cy) is the frame's outer
// corner and dx, dy point inward, so p(u, v) works for all four corners.
type corner struct{ cx, cy, dx, dy float64 }

func (c corner) p(u, v float64) string { return fmt.Sprintf("%g,%g", c.cx+c.dx*u, c.cy+c.dy*v) }

// sweep: the arc from the (0, r) side to the (r, 0) side turns clockwise on
// screen for the top-left and bottom-right corners.
func (c corner) sweep(flip bool) int {
	s := 0
	if c.dx*c.dy > 0 {
		s = 1
	}
	if flip {
		s = 1 - s
	}
	return s
}

// quarter is the filled corner: a quarter disc of radius r.
func (c corner) quarter(r float64) string {
	return fmt.Sprintf("M%s A%g,%g 0 0 %d %s L%s Z", c.p(0, r), r, r, c.sweep(false), c.p(r, 0), c.p(r, r))
}

// ring is the corner's 1 px outline, as a filled shape.
func (c corner) ring(r float64) string {
	return fmt.Sprintf("M%s A%g,%g 0 0 %d %s L%s A%g,%g 0 0 %d %s Z",
		c.p(0, r), r, r, c.sweep(false), c.p(r, 0), c.p(r, 1), r-1, r-1, c.sweep(true), c.p(1, r))
}

// mask is the blur region's corner, 1 px inside the drawn one (the mask is
// not antialiased; flush, its edge pixels would show past the curve). The
// degenerate corner points keep the bounding box the full slice.
func (c corner) mask(r float64) string {
	return fmt.Sprintf("M%s L%s L%s L%s A%g,%g 0 0 %d %s Z",
		c.p(0, r), c.p(r, r), c.p(r, 0), c.p(r, 1), r-1, r-1, c.sweep(true), c.p(1, r))
}

func fill(class string, opacity float64) string {
	return fmt.Sprintf(`class="%s" fill="currentColor" opacity="%g"`, class, opacity)
}

const outlineOpacity = 0.10 // as the window decoration's outline

// frameSVG lays out the frame slices, the blur mask and the shadow side by
// side. Slices are named as KSvg expects: topleft … bottomright, mask-*,
// shadow-*, and hint-* rectangles whose size gives a value.
func frameSVG(f frame) string {
	var d svgDoc
	r := f.radius
	bg := fill("ColorScheme-Background", f.opacity)
	line := fill("ColorScheme-Text", outlineOpacity)
	full := r + tile + r // a frame's side

	// The frame at (0, 0) and its mask at (full + 8, 0).
	for _, mask := range []bool{false, true} {
		ox, prefix := 0.0, ""
		if mask {
			ox, prefix = full+8, "mask-"
		}
		corners := map[string]corner{
			"topleft":     {ox, 0, 1, 1},
			"topright":    {ox + full, 0, -1, 1},
			"bottomleft":  {ox, full, 1, -1},
			"bottomright": {ox + full, full, -1, -1},
		}
		for name, c := range corners {
			if mask {
				d.add(`<path id="%s%s" d="%s"/>`, prefix, name, c.mask(r))
				continue
			}
			d.add(`<g id="%s"><path %s d="%s"/>`, name, bg, c.quarter(r))
			if f.outline {
				d.add(`<path %s d="%s"/>`, line, c.ring(r))
			}
			d.add(`</g>`)
		}
		sides := []struct {
			name       string
			x, y, w, h float64
			lx, ly     float64 // where the outline runs (1 px thick along the side)
		}{
			{"top", ox + r, 0, tile, r, ox + r, 0},
			{"bottom", ox + r, r + tile, tile, r, ox + r, full - 1},
			{"left", ox, r, r, tile, ox, r},
			{"right", ox + r + tile, r, r, tile, ox + full - 1, r},
		}
		for _, s := range sides {
			if mask {
				d.add(`<rect id="%s%s" x="%g" y="%g" width="%g" height="%g"/>`, prefix, s.name, s.x, s.y, s.w, s.h)
				continue
			}
			d.add(`<g id="%s"><rect %s x="%g" y="%g" width="%g" height="%g"/>`, s.name, bg, s.x, s.y, s.w, s.h)
			if f.outline {
				lw, lh := s.w, 1.0
				if s.name == "left" || s.name == "right" {
					lw, lh = 1, s.h
				}
				d.add(`<rect %s x="%g" y="%g" width="%g" height="%g"/>`, line, s.lx, s.ly, lw, lh)
			}
			d.add(`</g>`)
		}
		if mask {
			d.add(`<rect id="mask-center" x="%g" y="%g" width="%d" height="%d"/>`, ox+r, r, tile, tile)
		} else {
			d.add(`<rect id="center" %s x="%g" y="%g" width="%d" height="%d"/>`, bg, r, r, tile, tile)
		}
	}
	// Margins: content padding; insets: none.
	m := f.margin
	d.add(`<rect id="hint-top-margin" x="%g" y="0" width="4" height="%g" fill="#f0f"/>`, r, m)
	d.add(`<rect id="hint-bottom-margin" x="%g" y="0" width="4" height="%g" fill="#f0f"/>`, r+6, m)
	d.add(`<rect id="hint-left-margin" x="0" y="%g" width="%g" height="4" fill="#f0f"/>`, r, m)
	d.add(`<rect id="hint-right-margin" x="0" y="%g" width="%g" height="4" fill="#f0f"/>`, r+6, m)
	d.add(`<rect id="hint-tile-center" x="0" y="0" width="5" height="5" fill="#f60"/>`)

	defs := ""
	h := full
	if f.shadow > 0 {
		var defsB strings.Builder
		shadowSVG(&d, &defsB, f, 2*(full+8))
		defs = defsB.String()
		h = 2*(f.shadow+r) + tile
	}
	return d.String(2*(full+8)+2*(f.shadow+r)+tile, h, defs)
}

// shadowStops falls off roughly like a Gaussian from the frame's edge (at
// offset `from`) to nothing; under the frame it is transparent, since the
// glass would show it.
func shadowStops(from, depth float64) string {
	var b strings.Builder
	fmt.Fprintf(&b, `<stop offset="%g" stop-opacity="0"/>`, from)
	for _, s := range []struct{ t, k float64 }{{0, 1}, {0.2, 0.62}, {0.4, 0.3}, {0.6, 0.11}, {0.8, 0.03}, {1, 0}} {
		fmt.Fprintf(&b, `<stop offset="%g" stop-color="#000" stop-opacity="%g"/>`, from+(1-from)*s.t, depth*s.k)
	}
	return b.String()
}

// shadowSVG adds the shadow slices at x = ox. Each slice reaches s outside
// the frame and r under it (its corner), as Breeze's do.
func shadowSVG(d *svgDoc, defs *strings.Builder, f frame, ox float64) {
	s, r := f.shadow, f.radius
	n := s + r // a corner slice's side
	full := 2*n + tile
	inner := r / n // where the frame's edge sits along a gradient

	corners := map[string]corner{
		"topleft":     {ox, 0, 1, 1},
		"topright":    {ox + full, 0, -1, 1},
		"bottomleft":  {ox, full, 1, -1},
		"bottomright": {ox + full, full, -1, -1},
	}
	for name, c := range corners {
		// Centered on the frame corner's arc center, reaching the slice's outer corner.
		cx, cy := c.cx+c.dx*n, c.cy+c.dy*n
		fmt.Fprintf(defs, `<radialGradient id="g-%s" gradientUnits="userSpaceOnUse" cx="%g" cy="%g" r="%g">%s</radialGradient>`+"\n",
			name, cx, cy, n, shadowStops(inner, f.depth))
		x, y := min(c.cx, cx), min(c.cy, cy)
		d.add(`<rect id="shadow-%s" x="%g" y="%g" width="%g" height="%g" fill="url(#g-%s)"/>`, name, x, y, n, n, name)
	}
	// Sides: gradients from the frame edge outward.
	sides := []struct {
		name           string
		x, y, w, h     float64
		x1, y1, x2, y2 float64 // gradient from the inner end to the outer end
	}{
		{"top", ox + n, 0, tile, n, 0, n, 0, 0},
		{"bottom", ox + n, n + tile, tile, n, 0, n + tile, 0, full},
		{"left", ox, n, n, tile, ox + n, 0, ox, 0},
		{"right", ox + n + tile, n, n, tile, ox + n + tile, 0, ox + full, 0},
	}
	for _, sd := range sides {
		fmt.Fprintf(defs, `<linearGradient id="g-%s" gradientUnits="userSpaceOnUse" x1="%g" y1="%g" x2="%g" y2="%g">%s</linearGradient>`+"\n",
			sd.name, sd.x1, sd.y1, sd.x2, sd.y2, shadowStops(inner, f.depth))
		d.add(`<rect id="shadow-%s" x="%g" y="%g" width="%g" height="%g" fill="url(#g-%s)"/>`, sd.name, sd.x, sd.y, sd.w, sd.h, sd.name)
	}
	d.add(`<rect id="shadow-center" x="%g" y="%g" width="%d" height="%d" fill="#000" fill-opacity="0"/>`, ox+n, n, tile, tile)
	for _, side := range []string{"top", "bottom", "left", "right"} {
		w, h := 2.0, s
		if side == "left" || side == "right" {
			w, h = s, 2
		}
		d.add(`<rect id="shadow-hint-%s-margin" x="%g" y="0" width="%g" height="%g" fill="#f0f"/>`, side, ox, w, h)
	}
}

// headingSVG is the header and footer of popups (plasmoidheading): calm, as
// the windows' merged title bar and toolbar: the popup's own glass, with a
// hairline between header and content. The slices still follow the popup's
// corners so the header's box lines up.
func headingSVG(r float64) string {
	var d svgDoc
	clear := `fill="#000" fill-opacity="0"`
	line := fill("ColorScheme-Text", outlineOpacity)
	full := 2*r + tile
	for i, part := range []string{"header", "footer"} {
		ox := float64(i) * (full + 8)
		edge := full - 1.0 // the hairline: the header's bottom, the footer's top
		if part == "footer" {
			edge = 0
		}
		for _, row := range []struct {
			name string
			y, h float64
		}{{"top", 0, r}, {"", r, tile}, {"bottom", r + tile, r}} {
			for _, col := range []struct {
				name string
				x, w float64
			}{{"left", 0, r}, {"", r, tile}, {"right", r + tile, r}} {
				name := row.name + col.name
				if name == "" {
					name = "center"
				}
				x, y := ox+col.x, row.y
				d.add(`<g id="%s-%s"><rect %s x="%g" y="%g" width="%g" height="%g"/>`, part, name, clear, x, y, col.w, row.h)
				if edge >= y && edge < y+row.h {
					d.add(`<rect %s x="%g" y="%g" width="%g" height="1"/>`, line, x, edge, col.w)
				}
				d.add(`</g>`)
			}
		}
	}
	for _, side := range []string{"top", "bottom", "left", "right"} {
		d.add(`<rect id="hint-%s-margin" x="0" y="0" width="6" height="6" fill="#f0f"/>`, side)
	}
	return d.String(2*(full+8), full, "")
}
