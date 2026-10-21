package config

import (
	"bufio"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"

	"github.com/goccy/go-yaml"
)

// Config is a host with its modules merged: everything the machine should have.
type Config struct {
	Repo    string // the repo the config was read from
	Host    string
	Modules []string
	User    User
	Vars    map[string]string
	Install *Install

	Packages      []Item // repo and AUR packages
	LocalPackages []LocalPackage
	Services      []Item
	UserServices  []Item
	Files         []*File // sorted by target
	Ignore        []string
}

// Item is a declared name and the module (or host) that declared it first.
type Item struct {
	Name string
	From string
}

// LocalPackage is a module's pkg/ folder.
type LocalPackage struct {
	Names []string // pkgname from the PKGBUILD (several for split packages)
	Dir   string
	From  string
}

// Scope tells where a file goes.
type Scope int

const (
	System Scope = iota // under /
	Home                // under the user's home
)

// File is a file the machine should have.
type File struct {
	Target     string // /etc/… or ~/…
	Scope      Scope
	Source     string // the file in the repo; empty for a declared link
	Template   bool   // Source ends in .tmpl
	Link       string // when set, Target is a symlink to this
	Executable bool   // Source is executable in git
	Opts       FileOptions
	From       string
}

// Mode returns the file's mode: the declared one, or 0644/0755.
func (f *File) Mode() fs.FileMode {
	if f.Opts.Mode != "" {
		m, _ := strconv.ParseUint(string(f.Opts.Mode), 8, 32) // validated on load
		return fs.FileMode(m)
	}
	if f.Executable {
		return 0o755
	}
	return 0o644
}

var (
	nameRE = regexp.MustCompile(`^[a-z0-9][a-z0-9._+-]*$`)
	unitRE = regexp.MustCompile(`^[A-Za-z0-9@._:\\-]+\.(service|socket|timer|target|path|mount|automount|swap)$`)
	modeRE = regexp.MustCompile(`^0?[0-7]{3}$`)
)

// HostFile and ModuleFile are the YAML file names in each folder.
const (
	HostFile   = "host.yaml"
	ModuleFile = "module.yaml"
)

// Load reads hosts/<host>/host.yaml and the modules it lists from repo.
func Load(repo, host string) (*Config, error) {
	hostDir := filepath.Join(repo, "hosts", host)
	var h Host
	if err := readYAML(filepath.Join(hostDir, HostFile), &h); err != nil {
		if errors.Is(err, fs.ErrNotExist) {
			return nil, fmt.Errorf("no host %q: %s/%s does not exist", host, rel(repo, hostDir), HostFile)
		}
		return nil, err
	}
	if h.User.Name == "" {
		return nil, fmt.Errorf("%s: user.name is required", rel(repo, filepath.Join(hostDir, HostFile)))
	}

	c := &Config{
		Repo:    repo,
		Host:    host,
		Modules: h.Modules,
		User:    h.User,
		Vars:    h.Vars,
		Install: h.Install,
	}
	m := &merger{c: c, repo: repo, files: map[string]*File{}, seen: map[string]map[string]bool{}}

	for i, name := range h.Modules {
		if !nameRE.MatchString(name) {
			return nil, fmt.Errorf("%s: modules[%d]: %q is not a valid module name", rel(repo, filepath.Join(hostDir, HostFile)), i, name)
		}
		if slices.Contains(h.Modules[:i], name) {
			return nil, fmt.Errorf("%s: module %q is listed twice", rel(repo, filepath.Join(hostDir, HostFile)), name)
		}
		dir := filepath.Join(repo, "modules", name)
		if st, err := os.Stat(dir); err != nil || !st.IsDir() {
			return nil, fmt.Errorf("module %q: %s does not exist", name, rel(repo, dir))
		}
		var mod Module
		if err := readYAML(filepath.Join(dir, ModuleFile), &mod); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return nil, err
		}
		if err := m.add(name, dir, &mod, false); err != nil {
			return nil, err
		}
	}
	if err := m.add("host "+host, hostDir, &h.Module, true); err != nil {
		return nil, err
	}

	for _, f := range m.files {
		c.Files = append(c.Files, f)
	}
	sort.Slice(c.Files, func(i, j int) bool { return c.Files[i].Target < c.Files[j].Target })
	return c, nil
}

type merger struct {
	c     *Config
	repo  string
	files map[string]*File
	seen  map[string]map[string]bool // list name -> item -> declared
}

func (m *merger) union(list string, dst *[]Item, names []string, from string, valid func(string) bool, what string) error {
	if m.seen[list] == nil {
		m.seen[list] = map[string]bool{}
	}
	for _, n := range names {
		if !valid(n) {
			return fmt.Errorf("%s: %q is not a valid %s", from, n, what)
		}
		if !m.seen[list][n] {
			m.seen[list][n] = true
			*dst = append(*dst, Item{Name: n, From: from})
		}
	}
	return nil
}

// add merges one module (or the host, last) into the config.
func (m *merger) add(from, dir string, mod *Module, isHost bool) error {
	c := m.c
	if err := m.union("packages", &c.Packages, mod.Packages, from, nameRE.MatchString, "package name"); err != nil {
		return err
	}
	if err := m.union("services", &c.Services, mod.Services, from, unitRE.MatchString, "unit name"); err != nil {
		return err
	}
	if err := m.union("user-services", &c.UserServices, mod.UserServices, from, unitRE.MatchString, "unit name"); err != nil {
		return err
	}
	for _, g := range mod.Ignore {
		if !strings.HasPrefix(g, "/") {
			return fmt.Errorf("%s: ignore: %q must be an absolute path", from, g)
		}
		if _, err := filepath.Match(g, ""); err != nil {
			return fmt.Errorf("%s: ignore: %q: %v", from, g, err)
		}
		c.Ignore = append(c.Ignore, g)
	}

	if names, err := pkgbuildNames(filepath.Join(dir, "pkg", "PKGBUILD")); err == nil {
		c.LocalPackages = append(c.LocalPackages, LocalPackage{Names: names, Dir: filepath.Join(dir, "pkg"), From: from})
	} else if !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("%s: %v", from, err)
	}

	// Files from the system/ and home/ trees.
	own := map[string]bool{}
	for _, tree := range []struct {
		name   string
		scope  Scope
		prefix string
	}{{"system", System, "/"}, {"home", Home, "~/"}} {
		root := filepath.Join(dir, tree.name)
		err := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
			if err != nil {
				if errors.Is(err, fs.ErrNotExist) && p == root {
					return filepath.SkipDir
				}
				return err
			}
			if d.IsDir() || d.Name() == ".gitkeep" {
				return nil
			}
			r, _ := filepath.Rel(root, p)
			f := &File{Target: tree.prefix + filepath.ToSlash(r), Scope: tree.scope, From: from}
			info, err := os.Lstat(p)
			if err != nil {
				return err
			}
			switch {
			case info.Mode()&fs.ModeSymlink != 0:
				if f.Link, err = os.Readlink(p); err != nil {
					return err
				}
			case info.Mode().IsRegular():
				f.Source = p
				f.Executable = info.Mode()&0o111 != 0
				if strings.HasSuffix(f.Target, ".tmpl") {
					f.Target = strings.TrimSuffix(f.Target, ".tmpl")
					f.Template = true
				}
			default:
				return fmt.Errorf("%s: not a regular file or a link", rel(m.repo, p))
			}
			if prev, ok := m.files[f.Target]; ok {
				if !isHost || own[f.Target] {
					return fmt.Errorf("%s: %s is provided by both %s and %s", f.Target, rel(m.repo, p), prev.From, from)
				}
			}
			m.files[f.Target] = f
			own[f.Target] = true
			return nil
		})
		if err != nil {
			return err
		}
	}

	// Options and declared links.
	keys := make([]string, 0, len(mod.Files))
	for k := range mod.Files {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	for _, target := range keys {
		opts := mod.Files[target]
		where := fmt.Sprintf("%s: files: %s", from, target)
		scope := System
		switch {
		case strings.HasPrefix(target, "~/"):
			scope = Home
		case strings.HasPrefix(target, "/"):
		default:
			return fmt.Errorf("%s: the path must start with / or ~/", where)
		}
		if target != cleanTarget(target) {
			return fmt.Errorf("%s: write it as %s", where, cleanTarget(target))
		}
		if opts.Mode != "" && !modeRE.MatchString(string(opts.Mode)) {
			return fmt.Errorf("%s: mode %q is not an octal mode like \"0644\"", where, opts.Mode)
		}
		if scope == Home && (opts.Owner != "" || opts.Group != "") {
			return fmt.Errorf("%s: home files always belong to the user", where)
		}
		if opts.Link != "" {
			if own[target] {
				return fmt.Errorf("%s: declared as a link but also present in the %s tree", where, map[Scope]string{System: "system/", Home: "home/"}[scope])
			}
			src := filepath.Join(dir, filepath.FromSlash(opts.Link))
			if !strings.HasPrefix(src, dir+string(filepath.Separator)) {
				return fmt.Errorf("%s: link %q must stay inside %s", where, opts.Link, rel(m.repo, dir))
			}
			if _, err := os.Stat(src); err != nil {
				return fmt.Errorf("%s: link %q: %s does not exist", where, opts.Link, rel(m.repo, src))
			}
			if prev, ok := m.files[target]; ok && !isHost {
				return fmt.Errorf("%s: also provided by %s", where, prev.From)
			}
			m.files[target] = &File{Target: target, Scope: scope, Link: src, Opts: opts, From: from}
			own[target] = true
			continue
		}
		f, ok := m.files[target]
		if !ok {
			return fmt.Errorf("%s: no such file in system/ or home/ (or add link:)", where)
		}
		if !own[target] && !isHost {
			return fmt.Errorf("%s: the file belongs to %s", where, f.From)
		}
		if f.Link != "" {
			return fmt.Errorf("%s: options don't apply to a link", where)
		}
		f.Opts = opts
	}
	return nil
}

func cleanTarget(t string) string {
	if rest, ok := strings.CutPrefix(t, "~/"); ok {
		return "~/" + strings.TrimPrefix(filepath.Clean("/"+rest), "/")
	}
	return filepath.Clean(t)
}

// pkgbuildNames reads pkgname from a PKGBUILD without running it.
func pkgbuildNames(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		v, ok := strings.CutPrefix(strings.TrimSpace(sc.Text()), "pkgname=")
		if !ok {
			continue
		}
		v = strings.Trim(v, "()")
		var names []string
		for _, n := range strings.Fields(v) {
			names = append(names, strings.Trim(n, `'"`))
		}
		if len(names) > 0 {
			return names, nil
		}
	}
	if err := sc.Err(); err != nil {
		return nil, err
	}
	return nil, fmt.Errorf("%s: no pkgname= line", path)
}

func readYAML(path string, v any) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if err := yaml.UnmarshalWithOptions(data, v, yaml.DisallowUnknownField()); err != nil {
		return fmt.Errorf("%s:\n%s", path, yaml.FormatError(err, false, true))
	}
	return nil
}

func rel(repo, p string) string {
	if r, err := filepath.Rel(repo, p); err == nil && !strings.HasPrefix(r, "..") {
		return r
	}
	return p
}
