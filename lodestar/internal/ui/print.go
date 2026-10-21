// Package ui prints plans and asks questions on the terminal.
package ui

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/drift"
	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
)

// Style colours output when it goes to a terminal.
type Style struct{ Color bool }

func (s Style) wrap(code, text string) string {
	if !s.Color {
		return text
	}
	return "\033[" + code + "m" + text + "\033[0m"
}

func (s Style) Bold(t string) string   { return s.wrap("1", t) }
func (s Style) Dim(t string) string    { return s.wrap("2", t) }
func (s Style) Green(t string) string  { return s.wrap("32", t) }
func (s Style) Yellow(t string) string { return s.wrap("33", t) }
func (s Style) Red(t string) string    { return s.wrap("31", t) }
func (s Style) Cyan(t string) string   { return s.wrap("36", t) }

// IsTerminal tells whether f is a terminal.
func IsTerminal(f *os.File) bool {
	st, err := f.Stat()
	return err == nil && st.Mode()&os.ModeCharDevice != 0
}

// maxDiffLines bounds the diff shown for one file.
const maxDiffLines = 40

// PrintPlan shows the plan grouped by section, with diffs of changed files.
func PrintPlan(w io.Writer, p *plan.Plan, s Style) {
	sections := []struct {
		title string
		match func(*plan.Action) bool
	}{
		{"Packages", func(a *plan.Action) bool { return a.Phase == plan.PhasePackages || a.Phase == plan.PhaseAUR }},
		{"System", func(a *plan.Action) bool {
			return a.Phase == plan.PhaseSystem && a.Unit == "" && a.User == ""
		}},
		{"Units", func(a *plan.Action) bool { return a.Phase == plan.PhaseSystem && a.Unit != "" }},
		{"User " + p.User, func(a *plan.Action) bool { return a.User != "" }},
		{"Home", func(a *plan.Action) bool { return a.Phase == plan.PhaseHome && a.KDEFile == "" }},
		{"KDE", func(a *plan.Action) bool { return a.Phase == plan.PhaseHome && a.KDEFile != "" }},
	}
	for _, sec := range sections {
		var lines []string
		adopted, forgotten := 0, 0
		for _, a := range p.Actions {
			if !sec.match(a) {
				continue
			}
			switch {
			case a.Op == plan.OpAdopt:
				adopted++
				continue
			case a.Op == plan.OpForget && a.Why == "":
				forgotten++
				continue
			}
			lines = append(lines, describe(a, s)...)
		}
		if adopted > 0 {
			lines = append(lines, s.Dim(fmt.Sprintf("= %d already match: recorded as managed", adopted)))
		}
		if forgotten > 0 {
			lines = append(lines, s.Dim(fmt.Sprintf("= %d records of things already gone are dropped", forgotten)))
		}
		if len(lines) == 0 {
			continue
		}
		fmt.Fprintln(w, s.Bold(sec.title))
		for _, l := range lines {
			fmt.Fprintln(w, "  "+l)
		}
	}
	if len(p.Notes) > 0 {
		fmt.Fprintln(w, s.Bold("Notes"))
		for _, n := range p.Notes {
			fmt.Fprintln(w, "  "+s.Yellow("!")+" "+n)
		}
	}
}

func describe(a *plan.Action, s Style) []string {
	add, change, remove := s.Green("+"), s.Yellow("~"), s.Red("-")
	detail := func(parts ...string) string {
		var keep []string
		for _, p := range parts {
			if p != "" {
				keep = append(keep, p)
			}
		}
		return s.Dim(strings.Join(keep, " · "))
	}
	names := strings.Join(a.Names, " ")
	switch a.Op {
	case plan.OpInstall:
		return []string{fmt.Sprintf("%s install %s %s", add, names, detail("repo"))}
	case plan.OpInstallAUR:
		return []string{fmt.Sprintf("%s install %s %s", add, names, detail("AUR"))}
	case plan.OpAsExplicit:
		return []string{fmt.Sprintf("%s mark explicit %s %s", change, names, detail(a.Why))}
	case plan.OpEnable:
		target := "enable"
		if a.Global {
			target = "enable for every user"
		}
		return []string{fmt.Sprintf("%s %s %s %s", add, target, a.Unit, detail(a.Why, a.From))}
	case plan.OpDisable:
		return []string{fmt.Sprintf("%s disable %s %s", remove, a.Unit, detail(a.Why))}
	case plan.OpStartUser:
		return []string{fmt.Sprintf("%s start %s now %s", add, a.Unit, detail("systemctl --user"))}
	case plan.OpCreateUser:
		return []string{fmt.Sprintf("%s create %s %s", add, a.User, detail("shell "+a.Shell, "groups "+names))}
	case plan.OpSetShell:
		return []string{fmt.Sprintf("%s shell %s", change, a.Why)}
	case plan.OpAddGroups:
		return []string{fmt.Sprintf("%s groups %s", add, names)}
	case plan.OpRun:
		return []string{fmt.Sprintf("%s run %s %s", s.Cyan(">"), a.Command, detail(a.Why))}
	case plan.OpRemove, plan.OpRestorePackage, plan.OpRestoreOriginal:
		return []string{fmt.Sprintf("%s %s %s", remove, a.Display, detail(a.Why))}
	case plan.OpForget:
		target := a.Display
		if a.KDEID != "" {
			target = a.KDEID
		}
		return []string{fmt.Sprintf("%s %s %s", s.Yellow("!"), target, detail(a.Why))}
	case plan.OpKDE:
		id := a.KDEFile + " [" + strings.Join(a.KDEGroup, "][") + "] " + a.KDEKey
		switch {
		case a.Delete:
			return []string{fmt.Sprintf("%s %s %s", remove, id, detail(a.Why))}
		case a.OldValue == nil:
			return []string{fmt.Sprintf("%s %s = %s %s", add, id, quoteKDE(a.Value), detail(a.From))}
		default:
			return []string{fmt.Sprintf("%s %s = %s → %s %s", change, id, quoteKDE(*a.OldValue), quoteKDE(a.Value), detail(a.From))}
		}
	case plan.OpKDEList:
		out := []string{fmt.Sprintf("%s %s %s", change, a.Display, detail(a.Why, a.From))}
		return append(out, diffLines(a.Old, a.Content, s)...)
	case plan.OpLink:
		sym := change
		if a.Why == "new" {
			sym = add
		}
		return []string{fmt.Sprintf("%s %s → %s %s", sym, a.Display, a.LinkTo, detail(a.Why, a.From))}
	case plan.OpWrite:
		sym := change
		if a.Why == "new" {
			sym = add
		}
		out := []string{fmt.Sprintf("%s %s %s", sym, a.Display, detail(a.Why, a.From))}
		if a.Old != nil {
			if a.Secret {
				out = append(out, "    "+s.Dim("(uses secrets: not shown)"))
			} else {
				out = append(out, diffLines(a.Old, a.Content, s)...)
			}
		}
		return out
	}
	return []string{fmt.Sprintf("? %s %s", a.Op, a.Display)}
}

// quoteKDE shows a KDE value; tabs separate several shortcuts.
func quoteKDE(v string) string {
	if v == "" {
		return `""`
	}
	return strings.ReplaceAll(v, "\t", " | ")
}

func diffLines(old, new []byte, s Style) []string {
	var out []string
	lines := strings.Split(strings.TrimSuffix(Diff(old, new), "\n"), "\n")
	for i, l := range lines {
		if i == maxDiffLines {
			out = append(out, "    "+s.Dim(fmt.Sprintf("… %d more lines", len(lines)-i)))
			break
		}
		switch {
		case strings.HasPrefix(l, "@@"):
			l = s.Cyan(l)
		case strings.HasPrefix(l, "+"):
			l = s.Green(l)
		case strings.HasPrefix(l, "-"):
			l = s.Red(l)
		}
		out = append(out, "    "+l)
	}
	return out
}

// Ask reads one line from the terminal after showing prompt.
func Ask(prompt string) string {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return ""
	}
	defer tty.Close()
	fmt.Fprint(tty, prompt)
	answer, _ := bufio.NewReader(tty).ReadString('\n')
	return strings.TrimSpace(answer)
}

// Confirm asks a yes/no question on the terminal; no is the default.
func Confirm(question string) bool {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return false
	}
	defer tty.Close()
	fmt.Fprintf(tty, "%s [y/N] ", question)
	answer, _ := bufio.NewReader(tty).ReadString('\n')
	answer = strings.ToLower(strings.TrimSpace(answer))
	return answer == "y" || answer == "yes"
}

// PrintDrift shows a drift report with what to do about each part.
func PrintDrift(w io.Writer, r *drift.Report, s Style) {
	section := func(title, hint string, items []string) {
		if len(items) == 0 {
			return
		}
		fmt.Fprintf(w, "%s %s\n", s.Bold(title), s.Dim(hint))
		for _, it := range items {
			fmt.Fprintln(w, "  "+it)
		}
	}
	section("Packages installed by hand", "(add them to a module, or lodestar prune)", r.UndeclaredPackages)
	if !r.Plan.Empty() {
		fmt.Fprintf(w, "%s %s\n", s.Bold("Declared, but different on the machine"), s.Dim("(lodestar apply puts the repo's version back)"))
		PrintPlan(indent{w}, r.Plan, s)
	}
	section("Files in /etc no package owns", "(add them to a module's system/, or to an ignore: list)", r.UnownedFiles)
	var modified []string
	for _, b := range r.ModifiedFiles {
		modified = append(modified, b.Path+" "+s.Dim("("+b.Package+")"))
	}
	section("Package config files changed on the machine", "(add them to a module's system/)", modified)
	section("Units enabled by hand", "(add them to services:)", r.Units)
	section("User units enabled by hand", "(add them to user-services:)", r.GlobalUnits)
	section("Extra groups of the user", "(add them to user.groups)", r.ExtraGroups)
	if len(r.Unreadable) > 0 {
		fmt.Fprintf(w, "%s %d paths need root to check %s\n", s.Yellow("!"), len(r.Unreadable), s.Dim("(sudo lodestar drift)"))
	}
}

// indent prefixes every line written through it with two spaces.
type indent struct{ w io.Writer }

func (i indent) Write(p []byte) (int, error) {
	lines := strings.SplitAfter(string(p), "\n")
	for _, l := range lines {
		if l == "" {
			continue
		}
		if _, err := io.WriteString(i.w, "  "+l); err != nil {
			return 0, err
		}
	}
	return len(p), nil
}
