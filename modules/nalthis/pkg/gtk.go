package main

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"text/template"
)

// GTK: Breeze-GTK stays the theme and KDE keeps writing its colors.css; we
// add nalthis.css next to it, imported from gtk.css the way KDE imports
// colors.css. It gives libadwaita (GTK 4) apps our palette, which KDE's
// colors.css doesn't (it only defines Breeze's names), and GTK 3 apps our
// shapes: radii, filled checks and switches, tinted row selection, thin
// scrollbars. libadwaita only takes colors: its shapes stay Adwaita's.

const gtkImport = "@import 'nalthis.css';"

// The GTK 4 file: libadwaita's named colors (and Breeze-GTK 4's shapes for
// the few GTK 4 apps without libadwaita).
const gtk4CSS = `/* Nalthis: written by nalthis apply from the palette (modules/nalthis). */
@define-color accent_bg_color {{.Accent}};
@define-color accent_fg_color #ffffff;
@define-color accent_color {{.AccentText}};
@define-color window_bg_color {{.Pane}};
@define-color window_fg_color {{.Text}};
@define-color view_bg_color {{.Base}};
@define-color view_fg_color {{.Text}};
@define-color headerbar_bg_color {{.Raised}};
@define-color headerbar_fg_color {{.Text}};
@define-color headerbar_border_color {{.Text}};
@define-color headerbar_backdrop_color {{.Pane}};
@define-color headerbar_shade_color rgba(0, 0, 0, 0.36);
@define-color sidebar_bg_color {{.Pane}};
@define-color sidebar_fg_color {{.Text}};
@define-color sidebar_backdrop_color {{.Pane}};
@define-color secondary_sidebar_bg_color {{.Base}};
@define-color card_bg_color {{.Raised}};
@define-color card_fg_color {{.Text}};
@define-color dialog_bg_color {{.Pane}};
@define-color dialog_fg_color {{.Text}};
@define-color popover_bg_color {{.Overlay}};
@define-color popover_fg_color {{.Text}};
@define-color thumbnail_bg_color {{.Raised}};
@define-color thumbnail_fg_color {{.Text}};
@define-color destructive_bg_color {{.NegativeFill}};
@define-color destructive_fg_color #ffffff;
@define-color destructive_color {{.Negative}};
@define-color success_bg_color {{.PositiveFill}};
@define-color success_fg_color #ffffff;
@define-color success_color {{.Positive}};
@define-color warning_bg_color {{.NeutralFill}};
@define-color warning_fg_color rgba(0, 0, 0, 0.8);
@define-color warning_color {{.Neutral}};
@define-color error_bg_color {{.NegativeFill}};
@define-color error_fg_color #ffffff;
@define-color error_color {{.Negative}};
`

// The GTK 3 file: shapes over Breeze-GTK, as the Union style draws them.
const gtk3CSS = `/* Nalthis: written by nalthis apply from the palette (modules/nalthis). */
button, entry, spinbutton, combobox button, .linked > button,
textview, frame > border, scrolledwindow.frame, .view.frame {
  border-radius: 6px;
}
.linked:not(.vertical) > :not(:first-child) { border-top-left-radius: 0; border-bottom-left-radius: 0; }
.linked:not(.vertical) > :not(:last-child) { border-top-right-radius: 0; border-bottom-right-radius: 0; }
.linked.vertical > :not(:first-child) { border-top-left-radius: 0; border-top-right-radius: 0; }
.linked.vertical > :not(:last-child) { border-bottom-left-radius: 0; border-bottom-right-radius: 0; }

/* Menus and popovers: 10 px, the popups' radius. */
menu, .menu, .context-menu, popover, popover.background, .csd.popup decoration {
  border-radius: 10px;
}
menu menuitem:hover, .menu menuitem:hover, .context-menu menuitem:hover {
  background-color: {{.Accent}};
  color: #ffffff;
  border-radius: 4px;
}

/* Checks, radios and switches filled with the deep accent. */
check, radio {
  border-radius: 4px;
}
radio { border-radius: 50%; }
check:checked, check:indeterminate, radio:checked,
treeview.view check:checked, treeview.view radio:checked {
  background-image: none;
  background-color: {{.Accent}};
  border-color: {{.Accent}};
  color: #ffffff;
  -gtk-icon-source: -gtk-icontheme("object-select-symbolic");
}
radio:checked, treeview.view radio:checked {
  -gtk-icon-source: none;
  background-image: radial-gradient(circle, #ffffff 0%, #ffffff 22%, transparent 27%);
}
check:indeterminate { -gtk-icon-source: -gtk-icontheme("list-remove-symbolic"); }
switch:checked { background-color: {{.Accent}}; border-color: {{.Accent}}; }
scale highlight, progressbar progress, levelbar block.filled {
  background-color: {{.Accent}};
  border-color: {{.Accent}};
}

/* Selected rows: a tint of the accent under the normal text. */
row:selected, treeview.view:selected, iconview:selected, flowboxchild:selected,
.view:selected, textview text selection {
  background-color: {{.SelectionTint}};
  color: {{.Text}};
}

/* Thin pill scrollbars. */
scrollbar, scrollbar trough { background-color: transparent; border: none; }
scrollbar slider, scrollbar.vertical slider, scrollbar.horizontal slider {
  min-width: 4px;
  min-height: 4px;
  border-radius: 99px;
  border: 4px solid transparent;
  box-shadow: none;
  background-clip: padding-box;
  background-color: alpha({{.Text}}, 0.3);
}
scrollbar slider:hover, scrollbar.vertical slider:hover, scrollbar.horizontal slider:hover { background-color: alpha({{.Text}}, 0.5); }
scrollbar slider:active, scrollbar.vertical slider:active, scrollbar.horizontal slider:active { background-color: {{.Accent}}; }
`

var gtkTemplates = map[string]*template.Template{
	"gtk-3.0": template.Must(template.New("gtk3").Parse(gtk3CSS)),
	"gtk-4.0": template.Must(template.New("gtk4").Parse(gtk4CSS)),
}

// writeGTK writes nalthis.css into configDir/gtk-3.0 and gtk-4.0 and makes
// gtk.css import it, keeping what KDE put there.
func writeGTK(configDir string, k Knobs) error {
	p := Compute(k)
	hex := func(c RGB) string { return c.Hex() }
	data := map[string]string{
		"Accent": hex(p.Accent), "AccentText": hex(p.AccentText),
		"Base": hex(p.Base), "Pane": hex(p.Pane), "Raised": hex(p.Raised), "Overlay": hex(p.Overlay),
		"Text": hex(p.Text),
		// As the Union style: the view's color, 35% of the way to the accent.
		"SelectionTint": hex(mix(p.Base, p.Accent, 0.35)),
		"Negative":      hex(p.Negative), "Neutral": hex(p.Neutral), "Positive": hex(p.Positive),
		// Fills carry white text, so they're deeper than the text colors.
		"NegativeFill": hex(OKLCH(0.56, 0.15, 20)), "NeutralFill": hex(OKLCH(0.78, 0.13, 75)), "PositiveFill": hex(OKLCH(0.56, 0.12, 150)),
	}
	for dir, t := range gtkTemplates {
		var buf bytes.Buffer
		if err := t.Execute(&buf, data); err != nil {
			return err
		}
		d := filepath.Join(configDir, dir)
		if err := writeAtomic(filepath.Join(d, "nalthis.css"), buf.Bytes()); err != nil {
			return err
		}
		if err := ensureImport(filepath.Join(d, "gtk.css")); err != nil {
			return err
		}
	}
	return nil
}

// ensureImport adds our import to gtk.css, after KDE's (the later wins).
func ensureImport(path string) error {
	old, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	if strings.Contains(string(old), gtkImport) {
		return nil
	}
	text := strings.TrimRight(string(old), "\n")
	if text != "" {
		text += "\n"
	}
	return writeAtomic(path, []byte(fmt.Sprintf("%s%s\n", text, gtkImport)))
}
