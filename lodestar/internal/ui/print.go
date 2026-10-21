// Package ui prints plans and asks questions on the terminal.
package ui

import (
	"bufio"
	"fmt"
	"io"
	"os"
	"strings"

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
		{"Home", func(a *plan.Action) bool { return a.Phase == plan.PhaseHome }},
	}
	for _, sec := range sections {
		var lines []string
		adopted := 0
		for _, a := range p.Actions {
			if !sec.match(a) {
				continue
			}
			if a.Op == plan.OpAdopt {
				adopted++
				continue
			}
			lines = append(lines, describe(a, s)...)
		}
		if adopted > 0 {
			lines = append(lines, s.Dim(fmt.Sprintf("= %d files already match: recorded as managed", adopted)))
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
