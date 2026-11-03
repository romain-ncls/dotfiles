package plan

import (
	"fmt"
	"os/exec"
	"regexp"
	"slices"
	"strings"
	"unicode"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
)

// HyprlandShortcuts is where the modules' command shortcuts are written as
// Hyprland binds, for a host with Hyprland: modules/hyprland's config
// requires it.
const HyprlandShortcuts = "~/.local/share/lodestar/hyprland-shortcuts.lua"

// xkbKeymap gives the keymap of a keyboard layout as text (xkbcli is part
// of libxkbcommon). A variable for the tests.
var xkbKeymap = func(layout string) (string, error) {
	out, err := exec.Command("xkbcli", "compile-keymap", "--layout", layout).Output()
	if err != nil {
		return "", fmt.Errorf("xkbcli compile-keymap --layout %s: %w", layout, err)
	}
	return string(out), nil
}

// hyprlandShortcutFiles writes the command shortcuts (name, keys, run) as
// Hyprland binds, with the keys Plasma has them on. KDE's own actions
// (component, action) have no meaning there: modules/hyprland binds their
// equivalents itself.
func hyprlandShortcutFiles(c *config.Config) ([]*config.File, error) {
	i := slices.IndexFunc(c.Packages, func(p config.Item) bool { return p.Name == "hyprland" })
	if i < 0 {
		return nil, nil
	}
	keymap, err := xkbKeymap(kbLayout(c))
	if err != nil {
		return nil, err
	}
	levels := parseKeymap(keymap)

	var b strings.Builder
	b.WriteString("-- Written by lodestar (internal/plan/hyprland.go) from the modules'\n" +
		"-- shortcuts, with the keys Plasma has them on. Required by\n" +
		"-- modules/hyprland's config: change the modules, not this file.\n\n")
	for _, s := range c.Shortcuts {
		if s.Run == "" {
			continue
		}
		for _, k := range s.Keys {
			keys, err := hyprKeys(k, levels)
			if err != nil {
				return nil, fmt.Errorf("%s: shortcut %q: %w", s.From, s.Name, err)
			}
			fmt.Fprintf(&b, "hl.bind(%s, hl.dsp.exec_cmd(%s), { description = %s })\n",
				luaString(keys), luaString(s.Run), luaString(s.Name))
		}
	}
	return []*config.File{{
		Target:    HyprlandShortcuts,
		Scope:     config.Home,
		Generated: []byte(b.String()),
		From:      c.Packages[i].From,
	}}, nil
}

// kbLayout is the keyboard layout the host declares for Plasma (kxkbrc),
// which Hyprland's config uses too; the first one when there are several.
func kbLayout(c *config.Config) string {
	for _, k := range c.KDE {
		if k.File == "kxkbrc" && slices.Equal(k.Group, []string{"Layout"}) && k.Key == "LayoutList" && k.Value != "" {
			return strings.TrimSpace(strings.Split(k.Value, ",")[0])
		}
	}
	return "us"
}

// level is where a keysym is on the layout: on its key alone (1), or with
// Shift (2), with base the key's own keysym.
type level struct {
	base  string
	shift bool
}

var keyRE = regexp.MustCompile(`(?m)^\s*key\s+<[A-Za-z0-9+-]+>\s*\{[^\[\n]*\[\s*([^\]]*)\]`)

// parseKeymap reads the first two levels of each key of the first group.
func parseKeymap(keymap string) map[string]level {
	out := map[string]level{}
	for _, m := range keyRE.FindAllStringSubmatch(keymap, -1) {
		syms := strings.Split(m[1], ",")
		for i := range syms {
			syms[i] = strings.TrimSpace(syms[i])
		}
		if syms[0] == "" || syms[0] == "NoSymbol" {
			continue
		}
		if _, ok := out[syms[0]]; !ok {
			out[syms[0]] = level{base: syms[0]}
		}
		if len(syms) > 1 && syms[1] != "" && syms[1] != "NoSymbol" {
			if _, ok := out[syms[1]]; !ok {
				out[syms[1]] = level{base: syms[0], shift: true}
			}
		}
	}
	return out
}

// hyprKeys turns a key combination as Plasma writes it (Meta+Shift+Return,
// Meta+É, Launch (5), Meta+Num+*) into a Hyprland bind's. Hyprland matches
// a bind against the layout's keysyms without Shift, so a symbol typed with
// Shift (/ on AZERTY) becomes Shift and its key's own symbol (SHIFT +
// colon).
func hyprKeys(kde string, levels map[string]level) (string, error) {
	parts := strings.Split(kde, "+")
	if strings.HasSuffix(kde, "++") { // the + key itself
		parts = append(parts[:len(parts)-2], "+")
	}
	name := parts[len(parts)-1]
	mods := map[string]bool{}
	keypad := false
	for _, p := range parts[:len(parts)-1] {
		switch p {
		case "Meta":
			mods["SUPER"] = true
		case "Ctrl":
			mods["CTRL"] = true
		case "Alt":
			mods["ALT"] = true
		case "Shift":
			mods["SHIFT"] = true
		case "Num":
			keypad = true
		default:
			return "", fmt.Errorf("%q: unknown modifier %q", kde, p)
		}
	}

	sym, err := keysym(name, keypad)
	if err != nil {
		return "", fmt.Errorf("%q: %w", kde, err)
	}
	if !keypad && namedKeys[name] == "" && !launchRE.MatchString(name) && !fKeyRE.MatchString(name) {
		l, ok := levels[sym]
		if !ok {
			return "", fmt.Errorf("%q: %s is not on the layout without AltGr", kde, sym)
		}
		if l.shift {
			mods["SHIFT"] = true
		}
		sym = l.base
	}

	var out []string
	for _, m := range []string{"SUPER", "CTRL", "ALT", "SHIFT"} {
		if mods[m] {
			out = append(out, m)
		}
	}
	return strings.Join(append(out, sym), " + "), nil
}

var (
	launchRE = regexp.MustCompile(`^Launch \(([0-9A-F])\)$`)
	fKeyRE   = regexp.MustCompile(`^F[0-9]{1,2}$`)
)

// keysym is the X keysym name of a key as Qt names it.
func keysym(name string, keypad bool) (string, error) {
	if keypad {
		if s, ok := keypadKeys[name]; ok {
			return s, nil
		}
		if len(name) == 1 && name[0] >= '0' && name[0] <= '9' {
			return "KP_" + name, nil
		}
		return "", fmt.Errorf("no keypad key %q", name)
	}
	if s, ok := namedKeys[name]; ok {
		return s, nil
	}
	if m := launchRE.FindStringSubmatch(name); m != nil {
		return "XF86Launch" + m[1], nil
	}
	if fKeyRE.MatchString(name) {
		return name, nil
	}
	r := []rune(name)
	if len(r) != 1 {
		return "", fmt.Errorf("unknown key %q", name)
	}
	c := unicode.ToLower(r[0])
	switch {
	case c >= 'a' && c <= 'z', c >= '0' && c <= '9':
		return string(c), nil
	}
	if s, ok := symbolKeys[c]; ok {
		return s, nil
	}
	return "", fmt.Errorf("unknown key %q", name)
}

// Keys with a name, as Qt writes them (QKeySequence::PortableText).
var namedKeys = map[string]string{
	"Return": "Return", "Enter": "KP_Enter", "Space": "space", "Tab": "Tab",
	"Backspace": "BackSpace", "Esc": "Escape", "Del": "Delete", "Ins": "Insert",
	"Home": "Home", "End": "End", "PgUp": "Page_Up", "PgDown": "Page_Down",
	"Left": "Left", "Right": "Right", "Up": "Up", "Down": "Down",
	"Print": "Print", "ScrollLock": "Scroll_Lock", "Pause": "Pause", "Menu": "Menu",
	"Sleep": "XF86Sleep", "Wake Up": "XF86WakeUp", "Power Off": "XF86PowerOff",
	"Volume Up": "XF86AudioRaiseVolume", "Volume Down": "XF86AudioLowerVolume",
	"Volume Mute": "XF86AudioMute", "Microphone Mute": "XF86AudioMicMute",
	"Media Play": "XF86AudioPlay", "Media Pause": "XF86AudioPause",
	"Toggle Media Play/Pause": "XF86AudioPlay", "Media Stop": "XF86AudioStop",
	"Media Next": "XF86AudioNext", "Media Previous": "XF86AudioPrev",
	"Search": "XF86Search", "Calculator": "XF86Calculator", "Launch Mail": "XF86Mail",
	"Home Page":             "XF86HomePage",
	"Monitor Brightness Up": "XF86MonBrightnessUp", "Monitor Brightness Down": "XF86MonBrightnessDown",
}

var keypadKeys = map[string]string{
	"*": "KP_Multiply", "+": "KP_Add", "-": "KP_Subtract", "/": "KP_Divide",
	".": "KP_Decimal", "=": "KP_Equal", "Enter": "KP_Enter",
}

// Symbols by their keysym names: ASCII and the Latin-1 ones of European
// layouts.
var symbolKeys = map[rune]string{
	'!': "exclam", '"': "quotedbl", '#': "numbersign", '$': "dollar", '%': "percent",
	'&': "ampersand", '\'': "apostrophe", '(': "parenleft", ')': "parenright",
	'*': "asterisk", '+': "plus", ',': "comma", '-': "minus", '.': "period",
	'/': "slash", ':': "colon", ';': "semicolon", '<': "less", '=': "equal",
	'>': "greater", '?': "question", '@': "at", '[': "bracketleft", '\\': "backslash",
	']': "bracketright", '^': "asciicircum", '_': "underscore", '`': "grave",
	'{': "braceleft", '|': "bar", '}': "braceright", '~': "asciitilde",
	'²': "twosuperior", '³': "threesuperior", '°': "degree", '£': "sterling",
	'§': "section", 'µ': "mu", '¨': "diaeresis", '¤': "currency",
	'à': "agrave", 'â': "acircumflex", 'ä': "adiaeresis", 'ç': "ccedilla",
	'é': "eacute", 'è': "egrave", 'ê': "ecircumflex", 'ë': "ediaeresis",
	'î': "icircumflex", 'ï': "idiaeresis", 'ô': "ocircumflex", 'ö': "odiaeresis",
	'ù': "ugrave", 'û': "ucircumflex", 'ü': "udiaeresis", 'ñ': "ntilde", 'ß': "ssharp",
}

// luaString quotes s as a Lua long string, which keeps it as it is.
func luaString(s string) string {
	eq := ""
	for strings.Contains(s, "]"+eq+"]") || strings.HasSuffix(s, "]"+eq) {
		eq += "="
	}
	return "[" + eq + "[" + s + "]" + eq + "]"
}
