package plan

import (
	"path/filepath"
	"slices"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
)

// braveFlagsFile is Brave's command line, from the modules' brave: entries:
// their flags, then one --load-extension with every extension folder.
// Brave's launcher (/usr/bin/brave) reads it one argument per line and
// skips the lines starting with #. ~/ is expanded here: neither expands it.
func braveFlagsFile(c *config.Config, home string) []*config.File {
	if c.Brave == nil {
		return nil
	}
	var b strings.Builder
	b.WriteString("# Brave's command line, one argument per line, read by its launcher\n" +
		"# (/usr/bin/brave). Written by lodestar from the brave: entries of this\n" +
		"# host's modules.\n")
	for _, f := range c.Brave.Flags {
		b.WriteString(f.Name + "\n")
	}
	if len(c.Brave.Extensions) > 0 {
		var dirs []string
		for _, e := range c.Brave.Extensions {
			dir := e.Name
			if rest, ok := strings.CutPrefix(dir, "~/"); ok {
				dir = filepath.Join(home, rest)
			}
			dirs = append(dirs, dir)
		}
		b.WriteString("--load-extension=" + strings.Join(dirs, ",") + "\n")
	}
	return []*config.File{{
		Target:    config.BraveFlagsFile,
		Scope:     config.Home,
		Generated: []byte(b.String()),
		From:      "brave",
	}}
}

// braveRestart says when Brave has to restart to read new flags: it reads
// them only when it starts.
func (p *Plan) braveRestart(in Input) {
	path := p.Abs(config.BraveFlagsFile)
	if in.Root != "" || !slices.ContainsFunc(p.Actions, func(a *Action) bool { return a.Path == path }) {
		return
	}
	if running("brave") {
		p.note("Brave reads %s when it starts: restart it to load the change", config.BraveFlagsFile)
	}
}
