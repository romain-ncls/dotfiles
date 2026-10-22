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

	Firewall         *FirewallSpec // nil: no firewall
	KDE              []KDEKey      // sorted by file, group, key
	KDEIgnore        []string
	BreezeExceptions []KDEEntry
	WindowRules      []KDEEntry
	Shortcuts        []ShortcutItem
	JSON             []JSONTarget
	Hooks            []HookItem
	Limine           string // the hand-written part of limine.conf, or ""
}

// KDEKey is one key of a KDE config file.
type KDEKey struct {
	File  string
	Group []string // nested groups
	Key   string
	Value string
	From  string
}

// ID identifies the key: file/group/…/key.
func (k KDEKey) ID() string {
	return k.File + "/" + strings.Join(k.Group, "/") + "/" + k.Key
}

// KDEEntry is one entry of a KDE list (a Breeze exception, a window rule).
type KDEEntry struct {
	Keys map[string]string
	From string
}

// ShortcutItem is a declared shortcut.
type ShortcutItem struct {
	Shortcut
	From string
}

// DesktopFile is the .desktop file KDE uses for a command shortcut.
func (s ShortcutItem) DesktopFile() string {
	return "net.local.lodestar-" + slug(s.Name) + ".desktop"
}

// JSONTarget is a JSON file of $HOME and the files merged into it, in order.
type JSONTarget struct {
	Path          string   // ~/…
	Sources       []string // absolute paths in the repo
	UnlessRunning string
	From          string
}

// HookItem is a declared hook and where it runs.
type HookItem struct {
	Hook
	Dir  string // the module or host folder
	From string
}

// FirewallSpec is the merged firewall: the ports to open.
type FirewallSpec struct {
	TCP []string
	UDP []string
}

// Item is a declared name and the module (or host) that declared it first.
type Item struct {
	Name string
	From string
}

// LocalPackage is a module's pkg/ folder, or a PKGBUILD in another repo.
type LocalPackage struct {
	Names []string // pkgname from pkg/PKGBUILD; unknown for a git source until built
	Dir   string   // pkg/ folder; empty for a git source
	Watch []string // more folders whose changes rebuild it
	Git   string   // repo URL or local checkout (~/…)
	Ref   string
	Path  string // folder of the PKGBUILD in the git repo
	From  string
	// Module is the module's name (or the host's), naming a git source's
	// build folder.
	Module string
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
	Generated  []byte // content made by lodestar (a shortcut's .desktop file)
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
	m := &merger{c: c, repo: repo, files: map[string]*File{}, seen: map[string]map[string]bool{}, kde: map[string]int{}}

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
	if h.Boot != nil && h.Boot.Limine != "" {
		c.Limine = filepath.Join(hostDir, filepath.FromSlash(h.Boot.Limine))
		if _, err := os.Stat(c.Limine); err != nil {
			return nil, fmt.Errorf("host %s: boot.limine: %w", host, err)
		}
	}
	sort.Slice(c.KDE, func(i, j int) bool { return c.KDE[i].ID() < c.KDE[j].ID() })

	if c.Firewall != nil {
		if err := m.firewall(); err != nil {
			return nil, err
		}
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
	kde   map[string]int             // KDEKey.ID -> index in c.KDE
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

	if err := m.localPackage(from, dir, mod.Pkg); err != nil {
		return err
	}
	if err := m.rest(from, dir, mod); err != nil {
		return err
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
		if i := strings.Index(v, "#"); i >= 0 && (i == 0 || v[i-1] == ' ' || v[i-1] == '\t') {
			v = v[:i] // a comment
		}
		v = strings.Trim(strings.TrimSpace(v), "()")
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

var portRE = regexp.MustCompile(`^([0-9]{1,5})(-([0-9]{1,5}))?$`)

func (m *merger) localPackage(from, dir string, pkg *Pkg) error {
	c := m.c
	module := strings.TrimPrefix(from, "host ")
	names, err := pkgbuildNames(filepath.Join(dir, "pkg", "PKGBUILD"))
	hasDir := err == nil
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return fmt.Errorf("%s: %v", from, err)
	}
	var watch []string
	if pkg != nil {
		for _, w := range pkg.Watch {
			abs := filepath.Join(dir, filepath.FromSlash(w))
			if _, err := os.Stat(abs); err != nil {
				return fmt.Errorf("%s: pkg.watch: %w", from, err)
			}
			watch = append(watch, abs)
		}
	}
	switch {
	case pkg != nil && pkg.Git != "":
		if hasDir {
			return fmt.Errorf("%s: has both pkg/ and pkg.git; keep one", from)
		}
		if pkg.Ref == "" && !strings.HasPrefix(pkg.Git, "~/") && !strings.HasPrefix(pkg.Git, "/") {
			return fmt.Errorf("%s: pkg.ref is required with a remote pkg.git", from)
		}
		c.LocalPackages = append(c.LocalPackages, LocalPackage{Git: pkg.Git, Ref: pkg.Ref, Path: pkg.Path, Watch: watch, From: from, Module: module})
	case hasDir:
		c.LocalPackages = append(c.LocalPackages, LocalPackage{Names: names, Dir: filepath.Join(dir, "pkg"), Watch: watch, From: from, Module: module})
	case pkg != nil:
		return fmt.Errorf("%s: pkg: needs git:, or a pkg/ folder for watch:", from)
	}
	return nil
}

// rest merges the KDE settings, shortcuts, JSON keys, hooks and firewall.
func (m *merger) rest(from, dir string, mod *Module) error {
	c := m.c
	if mod.Firewall != nil {
		if c.Firewall == nil {
			c.Firewall = &FirewallSpec{}
		}
		for _, l := range []struct {
			name string
			in   []Value
			out  *[]string
		}{{"tcp", mod.Firewall.TCP, &c.Firewall.TCP}, {"udp", mod.Firewall.UDP, &c.Firewall.UDP}} {
			for _, v := range l.in {
				port := string(v)
				mm := portRE.FindStringSubmatch(port)
				if mm == nil || !validPort(mm[1]) || (mm[3] != "" && (!validPort(mm[3]) || atoi(mm[3]) <= atoi(mm[1]))) {
					return fmt.Errorf("%s: firewall.%s: %q is not a port or a range like 1714-1764", from, l.name, port)
				}
				if !slices.Contains(*l.out, port) {
					*l.out = append(*l.out, port)
				}
			}
		}
	}

	files := make([]string, 0, len(mod.KDE))
	for f := range mod.KDE {
		files = append(files, f)
	}
	sort.Strings(files)
	for _, file := range files {
		if file == "" || strings.Contains(file, "/") {
			return fmt.Errorf("%s: kde: %q must be a file name in ~/.config", from, file)
		}
		for group, keys := range mod.KDE[file] {
			path := strings.Split(group, "/")
			if slices.Contains(path, "") {
				return fmt.Errorf("%s: kde: %s: group %q has an empty part", from, file, group)
			}
			for key, val := range keys {
				if key == "" {
					return fmt.Errorf("%s: kde: %s: %s: empty key", from, file, group)
				}
				k := KDEKey{File: file, Group: path, Key: key, Value: string(val), From: from}
				if i, ok := m.kde[k.ID()]; ok {
					c.KDE[i] = k // a later module, or the host, wins
					continue
				}
				m.kde[k.ID()] = len(c.KDE)
				c.KDE = append(c.KDE, k)
			}
		}
	}
	c.KDEIgnore = append(c.KDEIgnore, mod.KDEIgnore...)

	for name, list := range map[string]struct {
		in  []map[string]Value
		out *[]KDEEntry
	}{"breeze-exceptions": {mod.BreezeExceptions, &c.BreezeExceptions}, "window-rules": {mod.WindowRules, &c.WindowRules}} {
		for i, e := range list.in {
			if len(e) == 0 {
				return fmt.Errorf("%s: %s[%d] is empty", from, name, i)
			}
			keys := map[string]string{}
			for k, v := range e {
				keys[k] = string(v)
			}
			*list.out = append(*list.out, KDEEntry{Keys: keys, From: from})
		}
	}

	for i, s := range mod.Shortcuts {
		where := fmt.Sprintf("%s: shortcuts[%d]", from, i)
		switch {
		case s.Run != "" && s.Name != "" && s.Component == "" && s.Action == "":
			if len(s.Keys) == 0 {
				return fmt.Errorf("%s: a command needs keys", where)
			}
			for _, other := range c.Shortcuts {
				if other.Run != "" && other.DesktopFile() == (ShortcutItem{Shortcut: s}).DesktopFile() {
					return fmt.Errorf("%s: the name %q is too close to %q (%s)", where, s.Name, other.Name, other.From)
				}
			}
		case s.Component != "" && s.Action != "" && s.Run == "" && s.Name == "":
		default:
			return fmt.Errorf("%s: write either name, keys and run (a command), or component, action and keys (a KDE action)", where)
		}
		c.Shortcuts = append(c.Shortcuts, ShortcutItem{Shortcut: s, From: from})
	}

	for i, j := range mod.JSON {
		where := fmt.Sprintf("%s: json[%d]", from, i)
		if !strings.HasPrefix(j.Path, "~/") {
			return fmt.Errorf("%s: path must start with ~/", where)
		}
		src := filepath.Join(dir, filepath.FromSlash(j.Merge))
		if _, err := os.Stat(src); err != nil {
			return fmt.Errorf("%s: merge: %w", where, err)
		}
		found := false
		for k := range c.JSON {
			if c.JSON[k].Path == j.Path {
				c.JSON[k].Sources = append(c.JSON[k].Sources, src)
				if j.UnlessRunning != "" {
					c.JSON[k].UnlessRunning = j.UnlessRunning
				}
				found = true
			}
		}
		if !found {
			c.JSON = append(c.JSON, JSONTarget{Path: j.Path, Sources: []string{src}, UnlessRunning: j.UnlessRunning, From: from})
		}
	}

	for i, h := range mod.Hooks {
		where := fmt.Sprintf("%s: hooks[%d]", from, i)
		if h.Run == "" {
			return fmt.Errorf("%s: run is required", where)
		}
		if h.As == "" {
			h.As = "user"
		}
		if h.When == "" {
			h.When = "changed"
		}
		if h.As != "user" && h.As != "root" {
			return fmt.Errorf("%s: as must be user or root", where)
		}
		if h.When != "changed" && h.When != "always" {
			return fmt.Errorf("%s: when must be changed or always", where)
		}
		c.Hooks = append(c.Hooks, HookItem{Hook: h, Dir: dir, From: from})
	}
	return nil
}

func validPort(s string) bool { n := atoi(s); return n >= 1 && n <= 65535 }

func atoi(s string) int {
	n := 0
	for _, ch := range s {
		n = n*10 + int(ch-'0')
	}
	return n
}

// slug turns a shortcut name into a file-name part.
func slug(name string) string {
	var sb strings.Builder
	dash := false
	for _, r := range strings.ToLower(name) {
		if (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') {
			sb.WriteRune(r)
			dash = false
		} else if !dash && sb.Len() > 0 {
			sb.WriteByte('-')
			dash = true
		}
	}
	return strings.TrimSuffix(sb.String(), "-")
}

// FirewallFile is the ruleset lodestar writes when a module declares firewall:.
const FirewallFile = "/etc/nftables.conf"

// firewall adds what the firewall needs: nftables, its unit, and the
// ruleset made from the declared ports.
func (m *merger) firewall() error {
	c := m.c
	const from = "firewall"
	if prev, ok := m.files[FirewallFile]; ok {
		return fmt.Errorf("%s: written by lodestar from the firewall: entries, so %s can't provide it", FirewallFile, prev.From)
	}
	m.union("packages", &c.Packages, []string{"nftables"}, from, nameRE.MatchString, "package name")
	m.union("services", &c.Services, []string{"nftables.service"}, from, unitRE.MatchString, "unit name")
	m.files[FirewallFile] = &File{
		Target:    FirewallFile,
		Scope:     System,
		Generated: []byte(Ruleset(c.Firewall)),
		From:      from,
		Opts: FileOptions{
			Check: "nft --check --file {}",
			Then:  "[ ! -d /run/systemd/system ] || nft --file " + FirewallFile,
		},
	}
	return nil
}

// Ruleset writes the nftables ruleset: incoming traffic is dropped except
// replies, loopback, ICMP, DHCPv6 replies, Docker's bridges and the ports.
func Ruleset(f *FirewallSpec) string {
	var sb strings.Builder
	sb.WriteString(`#!/usr/bin/nft -f
# Written by lodestar from the firewall: entries of this host's modules.
# Only this table is replaced; other tables (Docker's) are left alone.

destroy table inet lodestar
table inet lodestar {
	chain input {
		type filter hook input priority filter; policy drop;

		ct state established,related accept
		ct state invalid drop
		iif lo accept
		meta l4proto { icmp, ipv6-icmp } accept
		ip6 saddr fe80::/10 udp dport 546 accept comment "DHCPv6 replies"
		iifname "docker0" accept
		iifname "br-*" accept
`)
	for _, p := range []struct {
		proto string
		ports []string
	}{{"tcp", f.TCP}, {"udp", f.UDP}} {
		if len(p.ports) > 0 {
			fmt.Fprintf(&sb, "\t\t%s dport { %s } accept\n", p.proto, strings.Join(p.ports, ", "))
		}
	}
	sb.WriteString("\t}\n}\n")
	return sb.String()
}
