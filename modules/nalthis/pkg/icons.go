package main

import (
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"strings"
)

// The icon theme: Tela's color icons with our line icons for commands and
// the small (16–24 px) place and device icons, where Tela draws lines too,
// drawn from Lucide (icons.txt maps the names). Tela is linked inside our
// theme rather than inherited: lookups pick the closest size within a theme
// before trying the next, so an inherited Tela would lose its large place
// icons to our small ones wherever a name is in both.

//go:embed icons.txt
var iconMap string

// lineSizes are the sizes KDE draws line icons at (menus and sidebars 16,
// toolbars 22, GTK 24). Lucide is drawn on a 24 grid with 2 px strokes
// centered on whole coordinates; we put lines on pixel centers instead and
// draw them 1.5 px, the title bar glyphs' weight (1 px, KDE's rule, looked
// thin next to Tela's icons and the text).
// Plasma also asks for 32 px and more (tray popups, the panel). At 22 and
// 24 every line icon is the mockup's 18 px drawing, centered: at full size
// they looked heavy next to the text (popup headers, Kickoff). At 32 (the
// tray's grid of hidden items, list rows) the 22 px drawing sits centered,
// as Tela pads its own icons, so a slot doesn't fill with a giant glyph;
// [panel] names, glyphs sitting in the panel itself, stay at 18 there too.
// Places and devices stop at 24: larger, they are Tela's color icons
// (Dolphin's folders).
type lineSize struct {
	dir      string  // folder under line/
	size     int     // canvas
	scale    float64 // from Lucide's 24 grid
	shift    float64 // translation in pixels, after scaling
	strokePx float64
	contexts []string // nil: every context
	min, max int      // the sizes it serves (see writeIconTheme)
}

var lineSizes = []lineSize{
	{"16", 16, 2.0 / 3, 0.5, 1.5, nil, 12, 18}, // whole Lucide coordinates that are multiples of 3 land on pixels
	{"22", 22, 0.75, 2, 1.5, nil, 19, 23},      // the mockup's 18 px, centered
	{"24", 24, 0.75, 3, 1.5, nil, 24, 27},
	{"32", 32, 1, 4.5, 1.5, []string{"actions", "categories", "status"}, 28, 40}, // the 24 grid minus its empty 1 px border, centered
	{"32", 32, 0.75, 7, 1.5, []string{"panel"}, 28, 40},
	{"scalable", 32, 0.75, 7, 1.5, []string{"status", "panel"}, 41, 512},
}

func (s lineSize) has(ctx string) bool { return s.contexts == nil || slices.Contains(s.contexts, ctx) }

// iconContexts are the folders icons.txt's [sections] fill.
var iconContexts = map[string]string{"actions": "Actions", "places": "Places", "devices": "Devices", "categories": "Categories", "status": "Status", "panel": "Status"}

const lineColorStyle = `<style id="current-color-scheme" type="text/css">.ColorScheme-Text { color:#fcfcfc; }</style>`

var svgBody = regexp.MustCompile(`(?s)<svg[^>]*>(.*)</svg>`)

// lineIcon redraws one Lucide SVG at a size. KDE recolors it through the
// ColorScheme-Text class, like Breeze's monochrome icons.
func lineIcon(lucide []byte, size int, scale, shift, strokePx float64) (string, error) {
	m := svgBody.FindSubmatch(lucide)
	if m == nil {
		return "", fmt.Errorf("no <svg> element")
	}
	return fmt.Sprintf(`<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">
%s
<g class="ColorScheme-Text" fill="none" stroke="currentColor" stroke-width="%.4g" stroke-linecap="round" stroke-linejoin="round" transform="translate(%g %g) scale(%.6g)">%s</g>
</svg>
`, size, size, size, size, lineColorStyle, strokePx/scale, shift, shift, scale, strings.TrimSpace(string(m[1]))), nil
}

// writeIconTheme writes the theme to dir: our line icons, a link to Tela
// (telaDir, which must also exist at the same name next to dir once
// installed) and an index.theme listing ours first.
func writeIconTheme(lucideDir, telaDir, dir string) error {
	tela, err := readINI(filepath.Join(telaDir, "index.theme"))
	if err != nil {
		return err
	}
	var dirs []string
	var sections []Group
	for _, s := range lineSizes {
		for _, ctx := range []string{"actions", "places", "devices", "categories", "status", "panel"} {
			if !s.has(ctx) {
				continue
			}
			sub := fmt.Sprintf("line/%s/%s", s.dir, ctx)
			dirs = append(dirs, sub)
			// Scalable folders with adjoining ranges, not Fixed ones: a 20 or
			// 28 px request (Kirigami asks for those) takes our nearest
			// drawing, not a scalable Tela icon of the same name (often an
			// app's color icon). Lookups take the first folder that fits.
			keys := [][2]string{{"Size", fmt.Sprint(s.size)}, {"MinSize", fmt.Sprint(s.min)}, {"MaxSize", fmt.Sprint(s.max)},
				{"Context", iconContexts[ctx]}, {"Type", "Scalable"}}
			sections = append(sections, Group{Name: sub, Keys: keys})
			if err := os.MkdirAll(filepath.Join(dir, sub), 0o755); err != nil {
				return err
			}
		}
	}
	ctx := ""
	for _, line := range strings.Split(iconMap, "\n") {
		f := strings.Fields(line)
		if len(f) == 0 || strings.HasPrefix(f[0], "#") {
			continue
		}
		if c, ok := strings.CutPrefix(f[0], "["); ok {
			ctx = strings.TrimSuffix(c, "]")
			if iconContexts[ctx] == "" {
				return fmt.Errorf("icons.txt: unknown section %q", f[0])
			}
			continue
		}
		if len(f) != 2 || ctx == "" {
			return fmt.Errorf("icons.txt: bad line %q (or no [section] before it)", line)
		}
		src, err := os.ReadFile(filepath.Join(lucideDir, f[1]+".svg"))
		if err != nil {
			return err
		}
		// Each name also as its -symbolic twin, which Plasma asks for and
		// which Tela has (as its own line icons).
		names := []string{f[0]}
		if !strings.HasSuffix(f[0], "-symbolic") {
			names = append(names, f[0]+"-symbolic")
		}
		for _, s := range lineSizes {
			if !s.has(ctx) {
				continue
			}
			svg, err := lineIcon(src, s.size, s.scale, s.shift, s.strokePx)
			if err != nil {
				return fmt.Errorf("%s: %w", f[1], err)
			}
			for _, name := range names {
				path := filepath.Join(dir, fmt.Sprintf("line/%s/%s", s.dir, ctx), name+".svg")
				if err := os.WriteFile(path, []byte(svg), 0o644); err != nil {
					return err
				}
			}
		}
	}

	// Tela's folders, prefixed with the link's name.
	head := Group{Name: "Icon Theme", Keys: [][2]string{
		{"Name", "Nalthis"},
		{"Comment", "Tela's color icons, Lucide line icons for commands"},
		{"Inherits", "breeze-dark,hicolor"},
	}}
	var scaled []string
	for _, g := range tela {
		if g.Name != "Icon Theme" {
			g.Name = "tela/" + g.Name
			sections = append(sections, g)
			continue
		}
		for _, kv := range g.Keys {
			switch kv[0] {
			case "Name", "Comment", "Inherits":
			case "Directories", "ScaledDirectories":
				for _, d := range strings.Split(kv[1], ",") {
					if kv[0] == "Directories" {
						dirs = append(dirs, "tela/"+d)
					} else {
						scaled = append(scaled, "tela/"+d)
					}
				}
			case "ToolbarDefault", "MainToolbarDefault":
				// The mockup's 16 px toolbars (Tela, as Breeze: 22). KDE 6 takes
				// these sizes from the icon theme only.
				head.Keys = append(head.Keys, [2]string{kv[0], "16"})
			default:
				head.Keys = append(head.Keys, kv)
			}
		}
	}
	head.Keys = append(head.Keys, [2]string{"Directories", strings.Join(dirs, ",")})
	if len(scaled) > 0 {
		head.Keys = append(head.Keys, [2]string{"ScaledDirectories", strings.Join(scaled, ",")})
	}
	link := filepath.Join(dir, "tela")
	os.Remove(link)
	if err := os.Symlink(filepath.Join("..", filepath.Base(telaDir)), link); err != nil {
		return err
	}
	f, err := os.Create(filepath.Join(dir, "index.theme"))
	if err != nil {
		return err
	}
	defer f.Close()
	return writeINI(f, append([]Group{head}, sections...))
}
