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

// Knob describes one knob for the sliders: range, step and how to show it.
type Knob struct {
	Name, Label   string
	Min, Max      float64
	Step, BigStep float64
	Wrap          bool // hues go round
	Get           func(*Knobs) *float64
}

var KnobList = []Knob{
	{"hue", "Grey hue", 0, 360, 1, 10, true, func(k *Knobs) *float64 { return &k.Hue }},
	{"tint", "Tint", 0, 3, 0.05, 0.25, false, func(k *Knobs) *float64 { return &k.Tint }},
	{"depth", "Depth", -0.06, 0.08, 0.005, 0.02, false, func(k *Knobs) *float64 { return &k.Depth }},
	{"accent", "Accent hue", 0, 360, 1, 10, true, func(k *Knobs) *float64 { return &k.Accent }},
}

// Clamp keeps every knob in its range (hues wrap) and rounds away float noise.
func (k *Knobs) Clamp() {
	for _, kn := range KnobList {
		v := kn.Get(k)
		if kn.Wrap {
			*v = math.Mod(math.Mod(*v, kn.Max)+kn.Max, kn.Max)
		} else {
			*v = math.Min(kn.Max, math.Max(kn.Min, *v))
		}
		*v = math.Round(*v*1000) / 1000
	}
}

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

// Palette is every color the knobs produce.
type Palette struct {
	Frame, Base, Pane, Raised, Overlay RGB
	Text, Text2, Text3                 RGB
	// Two accents of one hue: a deep one for fills (light text on it reaches
	// ~4.5:1; Kirigami draws marks and text on fills in the scheme's light
	// text, so fills can't be pale) and a light one for text and links.
	Accent, AccentText                   RGB
	Visited, Negative, Neutral, Positive RGB
}

func Compute(k Knobs) Palette {
	c := baseChroma * k.Tint
	var s [5]RGB
	for i := range s {
		s[i] = OKLCH(surfaceL[i]+k.Depth, c*chromaRamp[i], k.Hue)
	}
	return Palette{
		Frame: s[0], Base: s[1], Pane: s[2], Raised: s[3], Overlay: s[4],
		Text: OKLCH(0.94, c*0.8, k.Hue), Text2: OKLCH(0.76, c*1.5, k.Hue), Text3: OKLCH(0.58, c*1.5, k.Hue),
		Accent: OKLCH(0.56, 0.13, k.Accent), AccentText: OKLCH(0.76, 0.12, k.Accent),
		Visited:  OKLCH(0.74, 0.12, 305),
		Negative: OKLCH(0.70, 0.14, 20), Neutral: OKLCH(0.80, 0.12, 75), Positive: OKLCH(0.78, 0.12, 150),
	}
}

// Tokens are the palette's main colors as hex, for previews.
func (p Palette) Tokens() map[string]string {
	return map[string]string{
		"frame": p.Frame.Hex(), "base": p.Base.Hex(), "pane": p.Pane.Hex(), "raised": p.Raised.Hex(),
		"overlay": p.Overlay.Hex(), "text": p.Text.Hex(), "text2": p.Text2.Hex(), "text3": p.Text3.Hex(),
		"accent": p.Accent.Hex(), "accentText": p.AccentText.Hex(),
	}
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
	p := Compute(k)
	group := func(name string, bg, alt RGB) Group {
		return Group{name, [][2]string{
			{"BackgroundNormal", bg.String()}, {"BackgroundAlternate", alt.String()},
			{"DecorationFocus", p.Accent.String()}, {"DecorationHover", p.Accent.String()},
			{"ForegroundActive", p.AccentText.String()}, {"ForegroundInactive", p.Text2.String()},
			{"ForegroundLink", p.AccentText.String()}, {"ForegroundNegative", p.Negative.String()},
			{"ForegroundNeutral", p.Neutral.String()}, {"ForegroundNormal", p.Text.String()},
			{"ForegroundPositive", p.Positive.String()}, {"ForegroundVisited", p.Visited.String()},
		}}
	}
	return []Group{
		{"General", [][2]string{{"Name", name}, {"ColorScheme", name}}},
		group("Colors:Window", p.Pane, p.Raised),
		group("Colors:View", p.Base, mix(p.Base, p.Pane, 0.5)),
		group("Colors:Button", p.Raised, p.Overlay),
		// Selection is the deep accent with light text: KDE also uses it as
		// "the accent" (Breeze folder icons, Plasma), so it can't be a dark
		// tint. The style draws selected list rows as a tint itself.
		group("Colors:Selection", p.Accent, mix(p.Accent, p.Base, 0.4)),
		group("Colors:Tooltip", p.Overlay, p.Raised),
		group("Colors:Complementary", p.Frame, p.Base),
		group("Colors:Header", p.Raised, p.Overlay),
		group("Colors:Header][Inactive", p.Pane, p.Raised),
		{"WM", [][2]string{
			{"activeBackground", p.Raised.String()}, {"activeBlend", p.Text.String()}, {"activeForeground", p.Text.String()},
			{"inactiveBackground", p.Pane.String()}, {"inactiveBlend", p.Text3.String()}, {"inactiveForeground", p.Text3.String()},
		}},
	}
}
