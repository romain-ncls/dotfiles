// Package drift finds what is on the machine but not in the repo.
package drift

import (
	"bufio"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
)

// Report is everything drift found.
type Report struct {
	// Explicitly installed packages the repo doesn't declare.
	UndeclaredPackages []string
	// Changes the plan would make: declared things that differ.
	Plan *plan.Plan
	// Files in /etc that no package owns and the repo doesn't declare.
	UnownedFiles []string
	// Package config files changed on the machine, not declared.
	ModifiedFiles []machine.Backup
	// Units enabled by hand: not declared, not enabled by a preset.
	Units, GlobalUnits []string
	// Groups the user is in beyond the declared ones.
	ExtraGroups []string
	// Paths that could not be read without root.
	Unreadable []string
}

// Empty tells whether the machine matches the repo.
func (r *Report) Empty() bool {
	return len(r.UndeclaredPackages) == 0 && r.Plan.Empty() && len(r.UnownedFiles) == 0 &&
		len(r.ModifiedFiles) == 0 && len(r.Units) == 0 && len(r.GlobalUnits) == 0 && len(r.ExtraGroups) == 0
}

// Generated files every Arch system has; the repo's `ignore:` lists add more.
var builtinIgnores = []string{
	"/etc/passwd", "/etc/passwd-", "/etc/group", "/etc/group-",
	"/etc/shadow", "/etc/shadow-", "/etc/gshadow", "/etc/gshadow-",
	"/etc/subuid", "/etc/subuid-", "/etc/subgid", "/etc/subgid-",
	"/etc/machine-id", "/etc/ld.so.cache", "/etc/adjtime", "/etc/.pwd.lock", "/etc/.updated",
	"/etc/pacman.d/gnupg/*", "/etc/ssl/certs/*", "/etc/ca-certificates/extracted/*",
	"/etc/udev/hwdb.bin", "/etc/*.lodestar",
}

// Find builds the report. p is the plan for the same config and machine.
func Find(c *config.Config, m machine.Machine, p *plan.Plan, root string) (*Report, error) {
	r := &Report{Plan: p}

	installed, err := m.Packages()
	if err != nil {
		return nil, err
	}
	declared := map[string]bool{}
	for _, it := range c.Packages {
		declared[it.Name] = true
	}
	for _, lp := range c.LocalPackages {
		for _, n := range lp.Names {
			declared[n] = true
		}
	}
	for name, pkg := range installed {
		if pkg.Explicit && !declared[name] {
			r.UndeclaredPackages = append(r.UndeclaredPackages, name)
		}
	}
	sort.Strings(r.UndeclaredPackages)

	ignore := compileGlobs(append(slices.Clone(builtinIgnores), c.Ignore...))
	if err := r.files(c, m, p, root, ignore); err != nil {
		return nil, err
	}
	if r.Units, err = units(m, c.Services, root, false); err != nil {
		return nil, err
	}
	if r.GlobalUnits, err = units(m, c.UserServices, root, true); err != nil {
		return nil, err
	}

	if u, err := m.User(c.User.Name); err != nil {
		return nil, err
	} else if u != nil {
		for _, g := range u.Groups {
			if g != u.PrimaryGroup && !slices.Contains(c.User.Groups, g) {
				r.ExtraGroups = append(r.ExtraGroups, g)
			}
		}
	}
	return r, nil
}

func (r *Report) files(c *config.Config, m machine.Machine, p *plan.Plan, root string, ignore []*regexp.Regexp) error {
	owned, err := m.OwnedFiles()
	if err != nil {
		return err
	}
	ignored := func(path string) bool {
		return slices.ContainsFunc(ignore, func(re *regexp.Regexp) bool { return re.MatchString(path) })
	}
	err = filepath.WalkDir(root+"/etc", func(phys string, d fs.DirEntry, err error) error {
		path := strings.TrimPrefix(phys, root)
		if err != nil {
			if errors.Is(err, fs.ErrPermission) {
				r.Unreadable = append(r.Unreadable, path)
				return filepath.SkipDir
			}
			return err
		}
		if ignored(path) {
			if d.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if d.IsDir() {
			return nil
		}
		if owned[path] {
			return nil
		}
		if _, ok := p.Desired[path]; ok {
			return nil
		}
		// Unit links are reported as units.
		if d.Type()&fs.ModeSymlink != 0 && strings.HasPrefix(path, "/etc/systemd/") {
			return nil
		}
		r.UnownedFiles = append(r.UnownedFiles, path)
		return nil
	})
	if err != nil {
		return err
	}

	backups, err := m.Backups()
	if err != nil {
		return err
	}
	for _, b := range backups {
		if _, ok := p.Desired[b.Path]; ok || ignored(b.Path) {
			continue
		}
		switch b.Status {
		case "modified":
			r.ModifiedFiles = append(r.ModifiedFiles, b)
		case "unmodified":
		default:
			r.Unreadable = append(r.Unreadable, b.Path)
		}
	}
	return nil
}

// units lists the enabled units that are neither declared, nor enabled by a
// preset, nor pulled in by a declared unit's Also=.
func units(m machine.Machine, declared []config.Item, root string, global bool) ([]string, error) {
	live, err := m.Units(global)
	if err != nil {
		return nil, err
	}
	dir := "/usr/lib/systemd/system"
	if global {
		dir = "/usr/lib/systemd/user"
	}
	want := map[string]bool{}
	for _, it := range declared {
		want[it.Name] = true
		for _, also := range alsoUnits(filepath.Join(root, dir, it.Name)) {
			want[also] = true
		}
	}
	var out []string
	for name, u := range live {
		if u.State == "enabled" && u.Preset != "enabled" && !want[name] {
			out = append(out, name)
		}
	}
	sort.Strings(out)
	return out, nil
}

// alsoUnits reads the Also= lines of a unit file.
func alsoUnits(path string) []string {
	f, err := os.Open(path)
	if err != nil {
		return nil
	}
	defer f.Close()
	var out []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if v, ok := strings.CutPrefix(strings.TrimSpace(sc.Text()), "Also="); ok {
			out = append(out, strings.Fields(v)...)
		}
	}
	return out
}

// compileGlobs turns shell-style globs into regexps. As in aconfmgr's
// IgnorePath, * also matches across slashes.
func compileGlobs(globs []string) []*regexp.Regexp {
	var out []*regexp.Regexp
	for _, g := range globs {
		var sb strings.Builder
		sb.WriteString("^")
		for _, ch := range g {
			switch ch {
			case '*':
				sb.WriteString(".*")
			case '?':
				sb.WriteString(".")
			default:
				sb.WriteString(regexp.QuoteMeta(string(ch)))
			}
		}
		sb.WriteString("$")
		out = append(out, regexp.MustCompile(sb.String()))
	}
	return out
}
