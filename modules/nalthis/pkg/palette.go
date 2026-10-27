package main

import (
	"fmt"
	"math"
)

// Knobs are the four settings of the palette: grey hue (degrees), tint
// (chroma multiplier), depth (lightness shift) and accent hue (degrees).
type Knobs struct {
	Hue    float64 `json:"hue"`
	Tint   float64 `json:"tint"`
	Depth  float64 `json:"depth"`
	Accent float64 `json:"accent"`
}

// Defaults is the "Custom from Nocturne" pick from the design page.
var Defaults = Knobs{Hue: 255, Tint: 1, Depth: 0, Accent: 250}

// Surfaces are an OKLCH ramp: frame, base, pane, raised, overlay.
var (
	surfaceL   = [5]float64{0.199, 0.229, 0.266, 0.299, 0.341}
	chromaRamp = [5]float64{0.9, 1, 1.15, 1.3, 1.5}
	baseChroma = 0.013
)

type RGB [3]uint8

func (c RGB) String() string { return fmt.Sprintf("%d,%d,%d", c[0], c[1], c[2]) }
func (c RGB) Hex() string    { return fmt.Sprintf("#%02x%02x%02x", c[0], c[1], c[2]) }

// OKLCH converts an OKLCH color to sRGB, clipping out-of-gamut channels.
func OKLCH(l, c, h float64) RGB {
	hr := h * math.Pi / 180
	a, b := c*math.Cos(hr), c*math.Sin(hr)
	l_ := l + 0.3963377774*a + 0.2158037573*b
	m_ := l - 0.1055613458*a - 0.0638541728*b
	s_ := l - 0.0894841775*a - 1.2914855480*b
	l3, m3, s3 := l_*l_*l_, m_*m_*m_, s_*s_*s_
	lin := [3]float64{
		4.0767416621*l3 - 3.3077115913*m3 + 0.2309699292*s3,
		-1.2684380046*l3 + 2.6097574011*m3 - 0.3413193965*s3,
		-0.0041960863*l3 - 0.7034186147*m3 + 1.7076147010*s3,
	}
	var out RGB
	for i, v := range lin {
		v = math.Min(1, math.Max(0, v))
		if v <= 0.0031308 {
			v *= 12.92
		} else {
			v = 1.055*math.Pow(v, 1/2.4) - 0.055
		}
		out[i] = uint8(math.Round(255 * v))
	}
	return out
}

func mix(a, b RGB, t float64) RGB {
	var out RGB
	for i := range a {
		out[i] = uint8(math.Round(float64(a[i]) + (float64(b[i])-float64(a[i]))*t))
	}
	return out
}

// Group is one KDE color group: key -> value, in file order.
type Group struct {
	Name string
	Keys [][2]string
}

// Scheme builds the KDE color scheme for the knobs. Calm chrome (layout A):
// content views are the darkest surface, windows and dialogs one step up,
// the header (toolbar + title bar, merged) one more.
func Scheme(name string, k Knobs) []Group {
	c := baseChroma * k.Tint
	var s [5]RGB
	for i := range s {
		s[i] = OKLCH(surfaceL[i]+k.Depth, c*chromaRamp[i], k.Hue)
	}
	_, base, pane, raised, overlay := s[0], s[1], s[2], s[3], s[4]
	fg, fg2, fg3 := OKLCH(0.94, c*0.8, k.Hue), OKLCH(0.76, c*1.5, k.Hue), OKLCH(0.58, c*1.5, k.Hue)
	// Two accents of one hue: a deep one for fills (light text on it reaches
	// ~4.5:1; Kirigami draws marks and text on fills in the scheme's light
	// text, so fills can't be pale) and a light one for text and links.
	acc, accText := OKLCH(0.56, 0.13, k.Accent), OKLCH(0.76, 0.12, k.Accent)
	visited := OKLCH(0.74, 0.12, 305)
	neg, neu, pos := OKLCH(0.70, 0.14, 20), OKLCH(0.80, 0.12, 75), OKLCH(0.78, 0.12, 150)

	group := func(name string, bg, alt RGB) Group {
		return Group{name, [][2]string{
			{"BackgroundNormal", bg.String()}, {"BackgroundAlternate", alt.String()},
			{"DecorationFocus", acc.String()}, {"DecorationHover", acc.String()},
			{"ForegroundActive", accText.String()}, {"ForegroundInactive", fg2.String()},
			{"ForegroundLink", accText.String()}, {"ForegroundNegative", neg.String()},
			{"ForegroundNeutral", neu.String()}, {"ForegroundNormal", fg.String()},
			{"ForegroundPositive", pos.String()}, {"ForegroundVisited", visited.String()},
		}}
	}
	return []Group{
		{"General", [][2]string{{"Name", name}, {"ColorScheme", name}}},
		group("Colors:Window", pane, raised),
		group("Colors:View", base, mix(base, pane, 0.5)),
		group("Colors:Button", raised, overlay),
		// Selection is the deep accent with light text: KDE also uses it as
		// "the accent" (Breeze folder icons, Plasma), so it can't be a dark
		// tint. The style draws selected list rows as a tint itself.
		group("Colors:Selection", acc, mix(acc, base, 0.4)),
		group("Colors:Tooltip", overlay, raised),
		group("Colors:Complementary", s[0], base),
		group("Colors:Header", raised, overlay),
		group("Colors:Header][Inactive", pane, raised),
		{"WM", [][2]string{
			{"activeBackground", raised.String()}, {"activeBlend", fg.String()}, {"activeForeground", fg.String()},
			{"inactiveBackground", pane.String()}, {"inactiveBlend", fg3.String()}, {"inactiveForeground", fg3.String()},
		}},
	}
}
