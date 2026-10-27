// nalthis generates the Nalthis color scheme from four knobs (grey hue, tint,
// depth, accent hue) and merges it into a kdeglobals.
package main

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strconv"
	"strings"
)

const usage = `usage:
  nalthis colors <name> [hue tint depth accent]   print a .colors file
  nalthis merge <kdeglobals> <scheme.colors>       print kdeglobals with the scheme's color groups
`

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, "nalthis:", err)
		os.Exit(1)
	}
}

func run(args []string, out io.Writer) error {
	if len(args) == 0 {
		return fmt.Errorf("no command\n%s", usage)
	}
	switch args[0] {
	case "colors":
		if len(args) != 2 && len(args) != 6 {
			return fmt.Errorf("colors takes a name and optionally 4 knobs\n%s", usage)
		}
		k := Defaults
		if len(args) == 6 {
			var v [4]float64
			for i, a := range args[2:] {
				f, err := strconv.ParseFloat(a, 64)
				if err != nil {
					return fmt.Errorf("knob %q: %w", a, err)
				}
				v[i] = f
			}
			k = Knobs{Hue: v[0], Tint: v[1], Depth: v[2], Accent: v[3]}
		}
		return writeINI(out, Scheme(args[1], k))
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

func readINI(path string) ([]Group, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var groups []Group
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		line := sc.Text()
		switch {
		case strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]"):
			groups = append(groups, Group{Name: line[1 : len(line)-1]})
		case len(groups) > 0 && strings.Contains(line, "="):
			k, v, _ := strings.Cut(line, "=")
			g := &groups[len(groups)-1]
			g.Keys = append(g.Keys, [2]string{k, v})
		}
	}
	return groups, sc.Err()
}

func writeINI(w io.Writer, groups []Group) error {
	bw := bufio.NewWriter(w)
	for _, g := range groups {
		fmt.Fprintf(bw, "[%s]\n", g.Name)
		for _, kv := range g.Keys {
			fmt.Fprintf(bw, "%s=%s\n", kv[0], kv[1])
		}
		fmt.Fprintln(bw)
	}
	return bw.Flush()
}
