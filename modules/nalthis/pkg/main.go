// nalthis is the Nalthis theme's palette: four knobs (grey hue, tint, depth,
// accent hue) saved in the dotfiles repo, turned into a KDE color scheme and
// applied live.
package main

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const usage = `usage:
  nalthis tune                                    adjust the knobs with the arrow keys, live
  nalthis get                                     print the saved knobs, the defaults and their colors (JSON)
  nalthis set [hue=N] [tint=N] [depth=N] [accent=N]  save knobs to the repo and apply them
  nalthis apply [hue tint depth accent]           apply the saved knobs, or these without saving
  nalthis tokens hue tint depth accent            print these knobs' colors (JSON)
  nalthis colors <name> [hue tint depth accent]   print a .colors file
  nalthis merge <kdeglobals> <scheme.colors>       print kdeglobals with the scheme's color groups
  nalthis konsole <dir> [hue tint depth accent]    write the Konsole color schemes into dir
  nalthis gtk <config-dir> [hue tint depth accent] write nalthis.css for GTK 3 and 4 (and its import)
  nalthis plasma-theme <dir>                      write the Plasma style (panel, popups) into dir
  nalthis icon-theme <lucide> <tela> <dir>        write the icon theme into dir: Lucide icons, linked Tela theme
`

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "nalthis:", err)
		os.Exit(1)
	}
}

// parseKnobs reads "hue tint depth accent" as four numbers.
func parseKnobs(args []string) (Knobs, error) {
	if len(args) != 4 {
		return Knobs{}, fmt.Errorf("expected 4 knobs (hue tint depth accent), got %d", len(args))
	}
	var v [4]float64
	for i, a := range args {
		f, err := strconv.ParseFloat(a, 64)
		if err != nil {
			return Knobs{}, fmt.Errorf("knob %q: %w", a, err)
		}
		v[i] = f
	}
	k := Knobs{Hue: v[0], Tint: v[1], Depth: v[2], Accent: v[3]}
	k.Clamp()
	return k, nil
}

func printJSON(out io.Writer, v any) error {
	enc := json.NewEncoder(out)
	enc.SetIndent("", "  ")
	return enc.Encode(v)
}

func run(args []string, out io.Writer) error {
	if len(args) == 0 {
		return fmt.Errorf("no command\n%s", usage)
	}
	switch args[0] {
	case "tune":
		return tune()
	case "get":
		k, err := loadKnobs()
		if err != nil {
			return err
		}
		return printJSON(out, map[string]any{"knobs": k, "defaults": Defaults, "tokens": Compute(k).Tokens()})
	case "tokens":
		k, err := parseKnobs(args[1:])
		if err != nil {
			return err
		}
		return printJSON(out, Compute(k).Tokens())
	case "set":
		k, err := loadKnobs()
		if err != nil {
			return err
		}
		for _, a := range args[1:] {
			name, val, ok := strings.Cut(a, "=")
			f, err := strconv.ParseFloat(val, 64)
			found := false
			for _, kn := range KnobList {
				if kn.Name == name {
					*kn.Get(&k), found = f, true
				}
			}
			if !ok || err != nil || !found {
				return fmt.Errorf("bad setting %q: use hue=, tint=, depth= or accent= with a number", a)
			}
		}
		k.Clamp()
		if err := saveKnobs(k); err != nil {
			return err
		}
		return apply(k)
	case "apply":
		k, err := loadKnobs()
		if len(args) > 1 {
			k, err = parseKnobs(args[1:])
		}
		if err != nil {
			return err
		}
		return apply(k)
	case "colors":
		if len(args) != 2 && len(args) != 6 {
			return fmt.Errorf("colors takes a name and optionally 4 knobs\n%s", usage)
		}
		k := Defaults
		if len(args) == 6 {
			var err error
			if k, err = parseKnobs(args[2:]); err != nil {
				return err
			}
		}
		return writeINI(out, Scheme(args[1], k))
	case "plasma-theme":
		if len(args) != 2 {
			return fmt.Errorf("plasma-theme takes a folder\n%s", usage)
		}
		return writePlasmaTheme(args[1])
	case "gtk":
		if len(args) != 2 && len(args) != 6 {
			return fmt.Errorf("gtk takes a folder and optionally 4 knobs\n%s", usage)
		}
		k, err := loadKnobs()
		if len(args) == 6 {
			k, err = parseKnobs(args[2:])
		}
		if err != nil {
			return err
		}
		return writeGTK(args[1], k)
	case "konsole":
		if len(args) != 2 && len(args) != 6 {
			return fmt.Errorf("konsole takes a folder and optionally 4 knobs\n%s", usage)
		}
		k, err := loadKnobs()
		if len(args) == 6 {
			k, err = parseKnobs(args[2:])
		}
		if err != nil {
			return err
		}
		return writeKonsoleSchemes(args[1], k)
	case "icon-theme":
		if len(args) != 4 {
			return fmt.Errorf("icon-theme takes three folders\n%s", usage)
		}
		return writeIconTheme(args[1], args[2], args[3])
	case "merge":
		if len(args) != 3 {
			return fmt.Errorf("merge takes two files\n%s", usage)
		}
		base, err := readINI(args[1])
		if err != nil {
			return err
		}
		scheme, err := readINI(args[2])
		if err != nil {
			return err
		}
		return writeINI(out, merge(base, scheme))
	}
	return fmt.Errorf("unknown command %q\n%s", args[0], usage)
}

// merge replaces every color group of base with the scheme's; [General] only
// takes the scheme's name as ColorScheme.
func merge(base, scheme []Group) []Group {
	out := append([]Group(nil), base...)
	find := func(name string) int {
		for i, g := range out {
			if g.Name == name {
				return i
			}
		}
		out = append(out, Group{Name: name})
		return len(out) - 1
	}
	for _, g := range scheme {
		if g.Name != "General" {
			out[find(g.Name)] = g
			continue
		}
		name := ""
		for _, kv := range g.Keys {
			if kv[0] == "ColorScheme" || (kv[0] == "Name" && name == "") {
				name = kv[1]
			}
		}
		i := find("General")
		set := false
		for j, kv := range out[i].Keys {
			if kv[0] == "ColorScheme" {
				out[i].Keys[j][1], set = name, true
			}
		}
		if !set {
			out[i].Keys = append(out[i].Keys, [2]string{"ColorScheme", name})
		}
	}
	return out
}

// rawLine marks a line kept as it is (a comment, a line without "=").
const rawLine = "\x00raw"

func readINI(path string) ([]Group, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var groups []Group
	sc := bufio.NewScanner(f)
	sc.Buffer(nil, 16<<20) // KDE values can be long (window states)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]"):
			groups = append(groups, Group{Name: line[1 : len(line)-1]})
		case strings.TrimSpace(line) == "":
		default:
			// Keys before any group (KConfig's default group) go in a group with
			// no name; comments are kept as they are.
			if len(groups) == 0 {
				groups = append(groups, Group{})
			}
			g := &groups[len(groups)-1]
			k, v, ok := strings.Cut(line, "=")
			if !ok || strings.HasPrefix(line, "#") {
				k, v = line, rawLine
			}
			g.Keys = append(g.Keys, [2]string{k, v})
		}
	}
	return groups, sc.Err()
}

func writeINI(w io.Writer, groups []Group) error {
	bw := bufio.NewWriter(w)
	for _, g := range groups {
		if g.Name != "" {
			fmt.Fprintf(bw, "[%s]\n", g.Name)
		}
		for _, kv := range g.Keys {
			if kv[1] == rawLine {
				fmt.Fprintln(bw, kv[0])
				continue
			}
			fmt.Fprintf(bw, "%s=%s\n", kv[0], kv[1])
		}
		fmt.Fprintln(bw)
	}
	return bw.Flush()
}
