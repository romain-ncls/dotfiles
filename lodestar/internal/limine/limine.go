// Package limine merges the hand-written part of /boot/limine.conf (global
// options, entries like Windows) with the part limine-entry-tool generates
// (the Arch Linux entry and its snapshots).
package limine

import (
	"regexp"
	"strings"
)

var entryRE = regexp.MustCompile(`^/[^/]`)

// split returns the global lines and the top-level entries (a line
// "/Title" and what follows it, until the next top-level entry).
func split(text string, dropComments bool) (globals []string, entries [][]string) {
	var cur []string
	for _, line := range strings.Split(text, "\n") {
		if entryRE.MatchString(line) {
			if cur != nil {
				entries = append(entries, cur)
			}
			cur = []string{line}
			continue
		}
		if cur == nil {
			if !dropComments || !strings.HasPrefix(line, "#") {
				globals = append(globals, line)
			}
			continue
		}
		cur = append(cur, line)
	}
	if cur != nil {
		entries = append(entries, cur)
	}
	return globals, entries
}

func trim(lines []string) []string {
	for len(lines) > 0 && strings.TrimSpace(lines[len(lines)-1]) == "" {
		lines = lines[:len(lines)-1]
	}
	for len(lines) > 0 && strings.TrimSpace(lines[0]) == "" {
		lines = lines[1:]
	}
	return lines
}

// Merge returns live with its globals and hand-written entries replaced by
// the repo's: generated entries first, then the repo's own. Comments of the
// repo file stay in the repo.
func Merge(repo, live string) string {
	rglob, rentries := split(repo, true)
	_, lentries := split(live, false)
	mine := map[string]bool{}
	for _, e := range rentries {
		mine[strings.TrimSpace(e[0])] = true
	}
	out := append(trim(rglob), "")
	for _, e := range lentries {
		if !mine[strings.TrimSpace(e[0])] {
			out = append(out, append(trim(e), "")...)
		}
	}
	for _, e := range rentries {
		out = append(out, append(trim(e), "")...)
	}
	return strings.Join(out, "\n")
}
