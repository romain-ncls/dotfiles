package main

import (
	"bytes"
	"fmt"
	"math"
	"path/filepath"
)

// Konsole color schemes from the palette: the terminal's background is the
// raised surface (headers, toolbars), lighter than the views' and close to
// One Dark's own (the views' looked too dark for a terminal), and the
// greys are the palette's. The six colors keep One Dark's hues and chroma
// (Romain's terminal and editor colors for years) at one lightness, so none
// is dimmer than another on our background. Blue and Red are the same with
// a tinted background, for kube and ssh sessions (modules/work, shell).

// oneDark is One Dark's red, green, yellow, blue, magenta and cyan.
var oneDark = [6]RGB{{224, 108, 117}, {152, 195, 121}, {209, 154, 102}, {97, 175, 239}, {198, 120, 221}, {86, 182, 194}}

// konsoleOpacity: the terminal is glass, as the panel: KWin blurs what is
// behind it (its blur effect, on in the host file), so text stays readable.
const konsoleOpacity = "0.88"

// Lightness of the six colors: normal, intense (bold), faint.
const ansiL, ansiIntenseL, ansiFaintL = 0.72, 0.80, 0.60

// konsoleTints are the schemes written, by name suffix: background chroma
// and hue (0 chroma: the palette's own surface).
var konsoleTints = []struct {
	suffix string
	chroma float64
	hue    float64
}{{"", 0, 0}, {"Blue", 0.04, 280}, {"Red", 0.04, 20}}

// toOKLCH is OKLCH's inverse: sRGB to lightness, chroma, hue.
func toOKLCH(c RGB) (l, ch, h float64) {
	var lin [3]float64
	for i, v := range c {
		f := float64(v) / 255
		if f <= 0.04045 {
			lin[i] = f / 12.92
		} else {
			lin[i] = math.Pow((f+0.055)/1.055, 2.4)
		}
	}
	l_ := math.Cbrt(0.4122214708*lin[0] + 0.5363325363*lin[1] + 0.0514459929*lin[2])
	m_ := math.Cbrt(0.2119034982*lin[0] + 0.6806995451*lin[1] + 0.1073969566*lin[2])
	s_ := math.Cbrt(0.0883024619*lin[0] + 0.2817188376*lin[1] + 0.6299787005*lin[2])
	l = 0.2104542553*l_ + 0.7936177850*m_ - 0.0040720468*s_
	a := 1.9779984951*l_ - 2.4285922050*m_ + 0.4505937099*s_
	b := 0.0259040371*l_ + 0.7827717662*m_ - 0.8086757660*s_
	return l, math.Hypot(a, b), math.Mod(math.Atan2(b, a)*180/math.Pi+360, 360)
}

// KonsoleScheme is one .colorscheme file.
func KonsoleScheme(p Palette, k Knobs, suffix string, tintC, tintH float64) []Group {
	bg := p.Raised
	if tintC > 0 {
		bg = OKLCH(surfaceL[3]+k.Depth, tintC, tintH)
	}
	// Black sits a step above the overlay, as the overlay above raised.
	black := OKLCH(surfaceL[4]+k.Depth+0.042, baseChroma*k.Tint*1.7, k.Hue)
	color := func(name string, c RGB) Group { return Group{Name: name, Keys: [][2]string{{"Color", c.String()}}} }
	groups := []Group{
		color("Background", bg), color("BackgroundFaint", bg), color("BackgroundIntense", bg),
		color("Foreground", p.Text2), color("ForegroundFaint", p.Text3), color("ForegroundIntense", p.Text),
		// Black: a step above the background (prompts' segments); bright black is the
		// hint grey, readable for comments and autosuggestions.
		color("Color0", black), color("Color0Faint", p.Overlay), color("Color0Intense", p.Text3),
	}
	for i, c := range oneDark {
		_, ch, h := toOKLCH(c)
		n := fmt.Sprintf("Color%d", i+1)
		groups = append(groups, color(n, OKLCH(ansiL, ch, h)), color(n+"Faint", OKLCH(ansiFaintL, ch*0.85, h)), color(n+"Intense", OKLCH(ansiIntenseL, ch, h)))
	}
	groups = append(groups, color("Color7", p.Text2), color("Color7Faint", p.Text3), color("Color7Intense", p.Text))
	name := schemeName
	if suffix != "" {
		name += " " + suffix
	}
	return append(groups, Group{Name: "General", Keys: [][2]string{
		{"Description", name}, {"Opacity", konsoleOpacity}, {"Blur", "true"}, {"ColorRandomization", "false"},
	}})
}

// writeKonsoleSchemes writes Nalthis, NalthisBlue and NalthisRed into dir.
func writeKonsoleSchemes(dir string, k Knobs) error {
	p := Compute(k)
	for _, t := range konsoleTints {
		var buf bytes.Buffer
		if err := writeINI(&buf, KonsoleScheme(p, k, t.suffix, t.chroma, t.hue)); err != nil {
			return err
		}
		if err := writeAtomic(filepath.Join(dir, schemeName+t.suffix+".colorscheme"), buf.Bytes()); err != nil {
			return err
		}
	}
	return nil
}
