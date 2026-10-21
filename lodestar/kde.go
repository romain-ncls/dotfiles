package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/glob"
	"github.com/romain-ncls/dotfiles/lodestar/internal/kdesnap"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/ui"
	"github.com/romain-ncls/dotfiles/lodestar/internal/yamledit"
)

func cmdKDE(o *options, args []string) error {
	if len(args) == 0 {
		return errors.New("usage: lodestar kde review [--list] | lodestar kde watch")
	}
	switch args[0] {
	case "review":
		return kdeReview(o, o.list)
	case "watch":
		return kdeWatch(o)
	}
	return fmt.Errorf("unknown kde command %q (review, watch)", args[0])
}

// userHome is the configured user's home directory.
func userHome(c *config.Config) (string, error) {
	u, err := machine.Local{}.User(c.User.Name)
	if err != nil {
		return "", err
	}
	if u == nil {
		return "", fmt.Errorf("user %s does not exist", c.User.Name)
	}
	return u.Home, nil
}

func kdeReview(o *options, list bool) error {
	c, err := o.load()
	if err != nil {
		return err
	}
	home, err := userHome(c)
	if err != nil {
		return err
	}
	snapPath := filepath.Join(home, kdesnap.Path)
	snap, err := kdesnap.Load(snapPath)
	if err != nil {
		return err
	}
	now, err := kdesnap.Take(filepath.Join(home, ".config"))
	if err != nil {
		return err
	}
	if snap == nil {
		fmt.Println("No snapshot yet: lodestar apply takes one. Taking it now; later changes will show here.")
		return now.Save(snapPath)
	}

	changes := reviewable(c, kdesnap.Diff(snap, now))
	if len(changes) == 0 {
		fmt.Println("No KDE setting changed since the last apply.")
		return nil
	}
	if list || !ui.IsTerminal(os.Stdin) {
		printChanges(changes)
		return nil
	}

	s := style()
	declared := map[string]config.KDEKey{}
	for _, k := range c.KDE {
		declared[k.ID()] = k
	}
	target := ""
	defer func() { snap.Save(snapPath) }()
	for i, ch := range changes {
		group, key := ch.GroupAndKey()
		fmt.Printf("\n%s %s %s %s\n", s.Dim(fmt.Sprintf("(%d/%d)", i+1, len(changes))), s.Bold(ch.File),
			s.Cyan("["+strings.Join(group, "][")+"]"), key+": "+describeChange(ch))
		d, isDeclared := declared[ch.ID()]
		if isDeclared {
			fmt.Println(s.Dim("  declared in " + d.From + " as " + d.Value))
		}
		options := "[k]eep  [i]gnore  [u]ndo  [s]kip  [q]uit"
		if ch.New == nil {
			options = "[i]gnore  [u]ndo  [s]kip  [q]uit"
		}
		switch answer := ui.Ask("  " + options + ": "); answer {
		case "k":
			if ch.New == nil {
				continue
			}
			dest := d.From
			if !isDeclared {
				if dest, err = chooseTarget(c, target); err != nil {
					return err
				}
				target = dest
			}
			if err := yamledit.SetKDEKey(yamlOf(c, dest), ch.File, group, key, *kdesnap.Value(ch.New)); err != nil {
				return err
			}
			snap.Set(ch.File, ch.Key, ch.New)
			fmt.Println(s.Green("  kept in " + dest))
		case "i":
			dest, err := chooseTarget(c, target)
			if err != nil {
				return err
			}
			target = dest
			if err := yamledit.AddToList(yamlOf(c, dest), "kde-ignore", ch.ID()); err != nil {
				return err
			}
			snap.Set(ch.File, ch.Key, ch.New)
			fmt.Println(s.Dim("  ignored in " + dest))
		case "u":
			if err := undoKDE(home, ch); err != nil {
				return err
			}
			fmt.Println(s.Yellow("  undone"))
		case "q":
			return nil
		}
	}
	return nil
}

// reviewable drops KDE's own state, ignored keys and the owned lists.
func reviewable(c *config.Config, changes []kdesnap.Change) []kdesnap.Change {
	ignore := glob.New(kdesnap.State, c.KDEIgnore)
	if len(c.BreezeExceptions) > 0 {
		ignore = append(ignore, glob.New([]string{"breezerc/Windeco Exception*"})...)
	}
	if len(c.WindowRules) > 0 {
		ignore = append(ignore, glob.New([]string{"kwinrulesrc/*"})...)
	}
	var out []kdesnap.Change
	for _, ch := range changes {
		if !ignore.Match(ch.ID()) && !ch.Binary() {
			out = append(out, ch)
		}
	}
	return out
}

func describeChange(ch kdesnap.Change) string {
	old, nw := kdesnap.Value(ch.Old), kdesnap.Value(ch.New)
	switch {
	case old == nil:
		return "(new) " + show(*nw)
	case nw == nil:
		return show(*old) + " (removed)"
	}
	return show(*old) + " → " + show(*nw)
}

func show(v string) string {
	if v == "" {
		return `""`
	}
	return strings.ReplaceAll(v, "\t", " | ")
}

// printChanges prints the changes as YAML for a module's kde: section.
func printChanges(changes []kdesnap.Change) {
	type entry struct {
		key, value, note string
	}
	tree := map[string]map[string][]entry{}
	var removed []string
	for _, ch := range changes {
		group, key := ch.GroupAndKey()
		old, nw := kdesnap.Value(ch.Old), kdesnap.Value(ch.New)
		if nw == nil {
			removed = append(removed, fmt.Sprintf("# removed: %s [%s] %s (was %s)", ch.File, strings.Join(group, "]["), key, show(*old)))
			continue
		}
		note := "new"
		if old != nil {
			note = "was " + show(*old)
		}
		g := strings.Join(group, "/")
		if tree[ch.File] == nil {
			tree[ch.File] = map[string][]entry{}
		}
		tree[ch.File][g] = append(tree[ch.File][g], entry{key, *nw, note})
	}
	fmt.Printf("# %d KDE keys changed\nkde:\n", len(changes))
	for _, file := range sortedKeys(tree) {
		fmt.Printf("  %s:\n", file)
		for _, g := range sortedKeys(tree[file]) {
			fmt.Printf("    %s:\n", yamlScalar(g))
			for _, e := range tree[file][g] {
				fmt.Printf("      %s: %s # %s\n", yamlScalar(e.key), yamlScalar(e.value), e.note)
			}
		}
	}
	for _, r := range removed {
		fmt.Println(r)
	}
}

func sortedKeys[V any](m map[string]V) []string {
	keys := make([]string, 0, len(m))
	for k := range m {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	return keys
}

func yamlScalar(s string) string {
	if s == "" || strings.ContainsAny(s, ":#{}[]&*!|>'\"%@`,\t\n") || strings.TrimSpace(s) != s {
		return strconv.Quote(s)
	}
	return s
}

// chooseTarget asks which module (or the host) gets a kept or ignored key.
func chooseTarget(c *config.Config, last string) (string, error) {
	choices := append(append([]string{}, c.Modules...), "host "+c.Host)
	var sb strings.Builder
	for i, m := range choices {
		fmt.Fprintf(&sb, "%d) %s  ", i+1, m)
	}
	def := ""
	if last != "" {
		def = " [" + last + "]"
	}
	for {
		answer := ui.Ask("  into " + sb.String() + def + ": ")
		if answer == "" && last != "" {
			return last, nil
		}
		if n, err := strconv.Atoi(answer); err == nil && n >= 1 && n <= len(choices) {
			return choices[n-1], nil
		}
		for _, m := range choices {
			if answer == m {
				return m, nil
			}
		}
	}
}

// yamlOf is the YAML file of a module, or of the host ("host NAME").
func yamlOf(c *config.Config, from string) string {
	if host, ok := strings.CutPrefix(from, "host "); ok {
		return filepath.Join(c.Repo, "hosts", host, config.HostFile)
	}
	return filepath.Join(c.Repo, "modules", from, config.ModuleFile)
}

// undoKDE writes a key's old value back, or deletes a new key.
func undoKDE(home string, ch kdesnap.Change) error {
	group, key := ch.GroupAndKey()
	args := []string{"--file", filepath.Join(home, ".config", ch.File)}
	for _, g := range group {
		args = append(args, "--group", g)
	}
	args = append(args, "--key", key)
	if ch.Old == nil {
		args = append(args, "--delete")
	} else {
		args = append(args, "--", *kdesnap.Value(ch.Old))
	}
	cmd := exec.Command("kwriteconfig6", args...)
	cmd.Stderr = os.Stderr
	return cmd.Run()
}

func kdeWatch(o *options) error {
	c, err := o.load()
	if err != nil {
		return err
	}
	home, err := userHome(c)
	if err != nil {
		return err
	}
	dir := filepath.Join(home, ".config")
	before, err := kdesnap.Take(dir)
	if err != nil {
		return err
	}
	ui.Ask("Change the setting in System Settings, then press Enter here.")
	after, err := kdesnap.Take(dir)
	if err != nil {
		return err
	}
	all := kdesnap.Diff(before, after)
	state := glob.New(kdesnap.State)
	var shown []kdesnap.Change
	for _, ch := range all {
		if !state.Match(ch.ID()) && !ch.Binary() {
			shown = append(shown, ch)
		}
	}
	if len(shown) == 0 {
		fmt.Println("No KDE setting changed.")
	} else {
		printChanges(shown)
	}
	if n := len(all) - len(shown); n > 0 {
		fmt.Printf("# (%d more keys changed that are KDE's own state)\n", n)
	}
	return nil
}
