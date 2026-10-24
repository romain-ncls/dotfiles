// Package plan compares the config with the machine and lists the actions
// that make the machine match.
package plan

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/user"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"syscall"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/limine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/render"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

// Phase orders the actions. Root phases run in the root process.
type Phase int

const (
	PhasePackages Phase = iota // root: pacman
	PhaseAUR                   // user: yay
	PhaseSystem                // root: files, follow-ups, units, user
	PhaseHome                  // user: home files
)

// Root tells whether the phase runs as root.
func (p Phase) Root() bool { return p == PhasePackages || p == PhaseSystem }

// Op is what an action does.
type Op string

const (
	OpInstall         Op = "install"          // pacman -S Names
	OpAsExplicit      Op = "explicit"         // pacman -D --asexplicit Names
	OpInstallAUR      Op = "install-aur"      // yay -S Names
	OpWrite           Op = "write"            // Content to Path
	OpLink            Op = "link"             // Path -> LinkTo
	OpRemove          Op = "remove"           // Path (if it still has ExpectHash/ExpectLink)
	OpRestorePackage  Op = "restore-package"  // Path from Package's archive
	OpRestoreOriginal Op = "restore-original" // Path from state.OriginalsDir
	OpRun             Op = "run"              // Command, through sh -c
	OpEnable          Op = "enable"           // Unit
	OpDisable         Op = "disable"          // Unit
	OpStartUser       Op = "start-user"       // Unit, systemctl --user (home phase)
	OpCreateUser      Op = "create-user"      // User with Shell and Names (groups)
	OpSetShell        Op = "shell"            // User's Shell
	OpAddGroups       Op = "groups"           // User's Names (groups)
	OpAdopt           Op = "adopt"            // the file already matches: only record it
	OpForget          Op = "forget"           // stop managing Path or KDEID, changed on the machine
	OpKDE             Op = "kde"              // set (or Delete) KDEFile/KDEGroup/KDEKey to Value
	OpKDEList         Op = "kde-list"         // rewrite the list of List in KDEFile as Entries
	OpJSON            Op = "json"             // write Content (the merged JSON) to Path
	OpHook            Op = "hook"             // run Command in Dir; record Hash under HookKey
	OpBuild           Op = "build"            // build and install the local package of Module
	OpLimine          Op = "limine"           // merge Value (the repo part) into /boot/limine.conf
)

// Action is one change. It travels as JSON to the root process.
type Action struct {
	Op    Op    `json:"op"`
	Phase Phase `json:"phase"`

	Path       string      `json:"path,omitempty"`    // absolute, without the root prefix
	Display    string      `json:"display,omitempty"` // as written in the repo: /etc/… or ~/…
	Content    []byte      `json:"content,omitempty"`
	Mode       fs.FileMode `json:"mode,omitempty"`
	Owner      string      `json:"owner,omitempty"`
	Group      string      `json:"group,omitempty"`
	LinkTo     string      `json:"link_to,omitempty"`
	Check      string      `json:"check,omitempty"`
	ExpectHash string      `json:"expect_hash,omitempty"`
	ExpectLink string      `json:"expect_link,omitempty"`
	Package    string      `json:"package,omitempty"`
	Original   bool        `json:"original,omitempty"` // the replaced file has no package: keep a copy
	Record     state.File  `json:"record,omitzero"`    // what the state file records once done

	Names   []string `json:"names,omitempty"`
	Unit    string   `json:"unit,omitempty"`
	Global  bool     `json:"global,omitempty"`
	User    string   `json:"user,omitempty"`
	Shell   string   `json:"shell,omitempty"`
	Command string   `json:"command,omitempty"`

	KDEFile  string              `json:"kde_file,omitempty"`
	KDEGroup []string            `json:"kde_group,omitempty"`
	KDEKey   string              `json:"kde_key,omitempty"`
	KDEID    string              `json:"kde_id,omitempty"`
	Value    string              `json:"value,omitempty"`
	OldValue *string             `json:"old_value,omitempty"` // nil: the key was not set
	Delete   bool                `json:"delete,omitempty"`
	List     string              `json:"list,omitempty"` // breeze or kwinrules
	Entries  []map[string]string `json:"entries,omitempty"`

	Dir     string `json:"dir,omitempty"` // hook: where it runs; build: the PKGBUILD's folder
	Hash    string `json:"hash,omitempty"`
	HookKey string `json:"hook_key,omitempty"`
	Always  bool   `json:"always,omitempty"` // a hook run on every apply
	// LiveOnly: a command for running daemons (udev, sysctl), skipped in a
	// chroot during an install.
	LiveOnly bool   `json:"live_only,omitempty"`
	Module   string `json:"module,omitempty"`
	Git      string `json:"git,omitempty"` // build: fetch Ref of Git first
	Ref      string `json:"ref,omitempty"`
	PkgPath  string `json:"pkg_path,omitempty"`
	Commit   string `json:"commit,omitempty"`

	From   string `json:"from,omitempty"`
	Why    string `json:"why,omitempty"`
	Secret bool   `json:"secret,omitempty"`
	Old    []byte `json:"-"` // the live content, for the diff
}

// Plan is the list of actions, in order.
type Plan struct {
	Repo    string // the repo the config comes from
	Root    string // prefix of the machine's filesystem ("" on a running system)
	Home    string // the user's home
	User    string
	Actions []*Action
	Notes   []string
	// Desired is every managed path and what lodestar should record for it.
	Desired map[string]state.File
	// LocalNames are the names of every local package (drift counts them
	// as declared, upgrade keeps yay away from them).
	LocalNames []string
}

// Input is what a plan is computed from.
type Input struct {
	Config  *config.Config
	Machine machine.Machine
	Root    string
	Facts   render.Facts
	Secrets render.Secrets
	System  *state.State // the system state file; nil loads it from the machine
	HomeSt  *state.State // the home state file; nil loads it from the machine
	// IDs resolves a user and a group name ("" for none) to ids; -1 when
	// unknown. Default: the running system's accounts.
	IDs func(user, group string) (uid, gid int)
	// Rebuild lists local packages to rebuild whatever their hash says
	// (lodestar upgrade: a library they use changed).
	Rebuild map[string]bool
	// Offline skips what needs the network (git ls-remote).
	Offline bool
}

// Compute builds the plan.
func Compute(in Input) (*Plan, error) {
	c := in.Config
	p := &Plan{Repo: c.Repo, Root: in.Root, User: c.User.Name, Desired: map[string]state.File{}}

	u, err := in.Machine.User(c.User.Name)
	if err != nil {
		return nil, err
	}
	p.Home = "/home/" + c.User.Name
	if u != nil {
		p.Home = u.Home
	}
	if in.System == nil {
		if in.System, err = state.Load(in.Root + state.SystemPath); err != nil {
			return nil, err
		}
	}
	if in.HomeSt == nil {
		if in.HomeSt, err = state.Load(in.Root + filepath.Join(p.Home, state.HomePath)); err != nil {
			return nil, err
		}
	}

	if err := p.packages(in); err != nil {
		return nil, err
	}
	r := render.New(c, p.Home, in.Root, in.Facts, in.Secrets)
	var errs []error
	for _, f := range c.Files {
		if f.Scope == config.System {
			errs = append(errs, p.file(in, r, f))
		}
	}
	errs = append(errs, p.removals(in, in.System, config.System))
	errs = append(errs, p.limine(in))
	p.followUps(in, PhaseSystem)
	errs = append(errs, p.units(in, false), p.units(in, true))
	p.user(in, u)
	home := append(slices.Clone(c.Files), shortcutFiles(c)...)
	for _, f := range home {
		if f.Scope == config.Home {
			errs = append(errs, p.file(in, r, f))
		}
	}
	errs = append(errs, p.kde(in))
	errs = append(errs, p.json(in))
	errs = append(errs, p.removals(in, in.HomeSt, config.Home))
	p.followUps(in, PhaseHome)
	p.startUserUnits(in)
	errs = append(errs, p.hooks(in))
	if err := errors.Join(errs...); err != nil {
		return nil, err
	}

	sort.SliceStable(p.Actions, func(i, j int) bool { return p.Actions[i].Phase < p.Actions[j].Phase })
	return p, nil
}

func (p *Plan) add(a *Action) { p.Actions = append(p.Actions, a) }

func (p *Plan) note(format string, args ...any) {
	p.Notes = append(p.Notes, fmt.Sprintf(format, args...))
}

// Empty tells whether there is nothing to do, apart from the hooks that run
// on every apply.
func (p *Plan) Empty() bool {
	return !slices.ContainsFunc(p.Actions, func(a *Action) bool { return !a.Always })
}

// HasRoot tells whether some action needs root.
func (p *Plan) HasRoot() bool {
	return slices.ContainsFunc(p.Actions, func(a *Action) bool { return a.Phase.Root() })
}

// Abs turns a repo target (/etc/… or ~/…) into an absolute path.
func (p *Plan) Abs(target string) string {
	if rest, ok := strings.CutPrefix(target, "~/"); ok {
		return filepath.Join(p.Home, rest)
	}
	return target
}

func (p *Plan) packages(in Input) error {
	installed, err := in.Machine.Packages()
	if err != nil {
		return err
	}
	var repo, aur, explicit []string
	var repos map[string]bool
	for _, it := range in.Config.Packages {
		pkg, ok := installed[it.Name]
		switch {
		case ok && !pkg.Explicit:
			explicit = append(explicit, it.Name)
		case ok:
		default:
			if repos == nil {
				if repos, err = in.Machine.InRepos(); err != nil {
					return err
				}
			}
			if repos[it.Name] {
				repo = append(repo, it.Name)
			} else {
				aur = append(aur, it.Name)
			}
		}
	}
	if err := p.localPackages(in, installed); err != nil {
		return err
	}
	if len(repo) > 0 {
		p.add(&Action{Op: OpInstall, Phase: PhasePackages, Names: repo})
	}
	if len(explicit) > 0 {
		p.add(&Action{Op: OpAsExplicit, Phase: PhasePackages, Names: explicit, Why: "installed as a dependency, now declared"})
	}
	if len(aur) > 0 {
		p.add(&Action{Op: OpInstallAUR, Phase: PhaseAUR, Names: aur})
	}
	return nil
}

// file compares one declared file with the machine.
func (p *Plan) file(in Input, r *render.Renderer, f *config.File) error {
	phase, owner, group := PhaseSystem, "root", "root"
	if f.Scope == config.Home {
		phase, owner, group = PhaseHome, p.User, ""
	}
	if f.Opts.Owner != "" {
		owner = f.Opts.Owner
	}
	if f.Opts.Group != "" {
		group = f.Opts.Group
	}
	path := p.Abs(f.Target)
	phys := in.Root + path
	a := &Action{Path: path, Display: f.Target, Phase: phase, From: f.From, Owner: owner, Group: group}

	live, err := os.Lstat(phys)
	exists := err == nil
	// Inside a root-only folder (/etc/sudoers.d) even lstat needs root.
	hidden := errors.Is(err, fs.ErrPermission)
	if err != nil && !errors.Is(err, fs.ErrNotExist) && !hidden {
		return fmt.Errorf("%s: %w", f.Target, err)
	}
	if exists && live.IsDir() {
		return fmt.Errorf("%s: is a directory on the machine; move it away, then apply again", f.Target)
	}

	st := in.System
	if f.Scope == config.Home {
		st = in.HomeSt
	}
	// upToDate records a file that already matches, if the state doesn't yet.
	upToDate := func() error {
		if rec := st.Files[path]; rec.Hash != a.Record.Hash || rec.Link != a.Record.Link || rec.From != a.Record.From {
			a.Op, a.Why = OpAdopt, "already matches"
			p.add(a)
		}
		return nil
	}

	// cantSee handles a file lodestar can't read: trust the state file if it
	// records this very content, otherwise let the root process write it.
	cantSee := func() error {
		if rec := st.Files[path]; rec.Hash == a.Record.Hash && rec.Link == a.Record.Link {
			return nil
		}
		a.Why = "can't read it without root"
		a.Original = p.mayNeedOriginal(in, f, path)
		p.add(a)
		return nil
	}

	if f.Link != "" {
		a.Op, a.LinkTo = OpLink, f.Link
		a.Record = state.File{Link: f.Link, From: f.From}
		p.Desired[path] = a.Record
		if hidden {
			return cantSee()
		}
		if !exists {
			a.Why = "new"
		} else if live.Mode()&fs.ModeSymlink == 0 {
			a.Why = "replaces a file"
			a.Original = p.mayNeedOriginal(in, f, path)
		} else if cur, _ := os.Readlink(phys); cur != f.Link {
			a.Why = "points to " + cur
			a.Original = p.mayNeedOriginal(in, f, path)
		} else {
			return upToDate()
		}
		p.add(a)
		return nil
	}

	var content []byte
	if f.Generated != nil {
		content = f.Generated
	} else if f.Template {
		content, a.Secret, err = r.Render(f.Source)
		if errors.Is(err, render.ErrLocked) {
			// Not comparable now; keep it declared so it isn't removed.
			p.Desired[path] = st.Files[path]
			p.note("%s: uses a Bitwarden secret and the vault is locked: not compared", f.Target)
			return nil
		}
		if err != nil {
			return fmt.Errorf("%s (%s): %w", f.Target, f.From, err)
		}
	} else if content, err = os.ReadFile(f.Source); err != nil {
		return err
	}
	a.Op, a.Content, a.Mode, a.Check = OpWrite, content, f.Mode(), f.Opts.Check
	hash := state.Hash(content)
	a.Record = state.File{Hash: hash, From: f.From}
	p.Desired[path] = a.Record

	switch {
	case hidden:
		return cantSee()
	case !exists:
		a.Why = "new"
	case live.Mode()&fs.ModeSymlink != 0:
		a.Why = "replaces a link"
	default:
		old, err := os.ReadFile(phys)
		switch {
		case errors.Is(err, fs.ErrPermission):
			return cantSee()
		case err != nil:
			return fmt.Errorf("%s: %w", f.Target, err)
		case string(old) != string(content):
			a.Why, a.Old = "content", old
		default:
			var changes []string
			if live.Mode().Perm() != a.Mode {
				changes = append(changes, fmt.Sprintf("mode %04o → %04o", live.Mode().Perm(), a.Mode))
			}
			ids := in.IDs
			if ids == nil {
				ids = systemIDs
			}
			wantUID, wantGID := ids(owner, group)
			if o, g := ownerOf(live); o != wantUID || (group != "" && g != wantGID) {
				changes = append(changes, "owner")
			}
			if len(changes) == 0 {
				return upToDate()
			}
			a.Why = strings.Join(changes, ", ")
		}
		a.Original = p.mayNeedOriginal(in, f, path)
	}
	p.add(a)
	if f.Opts.Then != "" {
		p.add(&Action{Op: OpRun, Phase: phase, Command: f.Opts.Then, Why: "then: " + f.Target})
	}
	return nil
}

// mayNeedOriginal tells whether replacing path loses a file no package owns
// (and lodestar did not write), which must then be kept.
func (p *Plan) mayNeedOriginal(in Input, f *config.File, path string) bool {
	if f.Scope != config.System || in.Root != "" {
		return false
	}
	if _, ours := in.System.Files[path]; ours {
		return false
	}
	owner, err := in.Machine.Owner(path)
	return err == nil && owner == ""
}

// removals undoes what the state file records and the config dropped.
func (p *Plan) removals(in Input, st *state.State, scope config.Scope) error {
	phase := PhaseSystem
	if scope == config.Home {
		phase = PhaseHome
	}
	paths := make([]string, 0, len(st.Files))
	for path := range st.Files {
		if _, keep := p.Desired[path]; !keep {
			paths = append(paths, path)
		}
	}
	sort.Strings(paths)
	for _, path := range paths {
		rec := st.Files[path]
		display := path
		if scope == config.Home {
			if rest, ok := strings.CutPrefix(path, p.Home+"/"); ok {
				display = "~/" + rest
			}
		}
		live, err := os.Lstat(in.Root + path)
		if errors.Is(err, fs.ErrNotExist) {
			continue // already gone; the new state forgets it
		}
		// A file lodestar can't see without root is checked by the root
		// process instead (ExpectHash, ExpectLink).
		hidden := errors.Is(err, fs.ErrPermission)
		if err != nil && !hidden {
			return err
		}
		a := &Action{Phase: phase, Path: path, Display: display, From: rec.From, ExpectHash: rec.Hash, ExpectLink: rec.Link}
		if !hidden && changedSince(in.Root+path, live, rec) {
			p.add(&Action{Op: OpForget, Phase: phase, Path: path, Display: display, Why: "no longer declared, but changed on the machine since lodestar wrote it: left as it is"})
			continue
		}
		switch {
		case scope == config.Home:
			a.Op, a.Why = OpRemove, "no longer declared"
		case rec.Original:
			a.Op, a.Why = OpRestoreOriginal, "no longer declared: the original comes back"
		default:
			owner, err := in.Machine.Owner(path)
			if err != nil {
				return err
			}
			if owner != "" {
				a.Op, a.Package, a.Why = OpRestorePackage, owner, "no longer declared: "+owner+"'s version comes back"
			} else {
				a.Op, a.Why = OpRemove, "no longer declared"
			}
		}
		p.add(a)
	}
	return nil
}

// changedSince tells whether a file or link differs from what lodestar wrote.
// An unreadable file counts as unchanged: the root process checks it.
func changedSince(phys string, live fs.FileInfo, rec state.File) bool {
	if rec.Link != "" {
		cur, _ := os.Readlink(phys)
		return live.Mode()&fs.ModeSymlink == 0 || cur != rec.Link
	}
	old, err := os.ReadFile(phys)
	return err == nil && state.Hash(old) != rec.Hash
}

// followUps adds the commands that must run after some files change.
func (p *Plan) followUps(in Input, phase Phase) {
	seen := map[string]bool{}
	for _, a := range slices.Clone(p.Actions) {
		if a.Phase != phase || a.Path == "" || a.Op == OpRun {
			continue
		}
		for _, cmd := range followUpsFor(a.Path, p.Home, phase) {
			if !seen[cmd] {
				seen[cmd] = true
				live := strings.HasPrefix(cmd, "udevadm") || strings.HasPrefix(cmd, "sysctl") || strings.HasPrefix(cmd, "systemctl --user")
				p.add(&Action{Op: OpRun, Phase: phase, Command: cmd, Why: "after " + a.Display, LiveOnly: live})
			}
		}
	}
}

const rebuildInitramfs = "if command -v limine-mkinitcpio >/dev/null; then limine-mkinitcpio; else mkinitcpio -P; fi"

func followUpsFor(path, home string, phase Phase) []string {
	if phase == PhaseHome {
		if strings.HasPrefix(path, filepath.Join(home, ".config/systemd")+"/") {
			return []string{"systemctl --user daemon-reload"}
		}
		return nil
	}
	switch {
	case path == "/etc/locale.gen":
		return []string{"locale-gen"}
	case strings.HasPrefix(path, "/etc/udev/rules.d/"), strings.HasPrefix(path, "/etc/udev/hwdb.d/"):
		return []string{"udevadm control --reload", "udevadm trigger"}
	case strings.HasPrefix(path, "/etc/systemd/"):
		return []string{"systemctl daemon-reload"}
	case path == "/etc/mkinitcpio.conf", strings.HasPrefix(path, "/etc/mkinitcpio.conf.d/"), strings.HasPrefix(path, "/etc/initcpio/"), path == "/etc/kernel/cmdline":
		return []string{rebuildInitramfs}
	case strings.HasPrefix(path, "/etc/sysctl.d/"):
		return []string{"sysctl --system"}
	}
	return nil
}

func (p *Plan) units(in Input, global bool) error {
	declared, kind := in.Config.Services, "system"
	if global {
		declared, kind = in.Config.UserServices, "global"
	}
	live, err := in.Machine.Units(global)
	if err != nil {
		return err
	}
	var errs []string
	want := map[string]bool{}
	for _, it := range declared {
		want[it.Name] = true
		u, ok := live[it.Name]
		switch {
		case !ok:
			p.add(&Action{Op: OpEnable, Phase: PhaseSystem, Unit: it.Name, Global: global, From: it.From, Why: "not installed yet"})
		case u.State == "enabled", u.State == "enabled-runtime":
		case u.State == "disabled", u.State == "indirect":
			p.add(&Action{Op: OpEnable, Phase: PhaseSystem, Unit: it.Name, Global: global, From: it.From})
		case u.State == "masked":
			errs = append(errs, fmt.Sprintf("%s (%s) is masked: unmask it or drop it", it.Name, it.From))
		default:
			errs = append(errs, fmt.Sprintf("%s (%s) is %s: it can't be enabled itself; declare the unit that wants it", it.Name, it.From, u.State))
		}
	}
	for _, key := range in.System.Units {
		k, name, _ := strings.Cut(key, ":")
		if k != kind || want[name] {
			continue
		}
		if u, ok := live[name]; ok && u.State == "enabled" {
			p.add(&Action{Op: OpDisable, Phase: PhaseSystem, Unit: name, Global: global, Why: "no longer declared"})
		}
	}
	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "\n"))
	}
	return nil
}

func (p *Plan) startUserUnits(in Input) {
	if in.Root != "" {
		return
	}
	for _, a := range slices.Clone(p.Actions) {
		if a.Op == OpEnable && a.Global {
			p.add(&Action{Op: OpStartUser, Phase: PhaseHome, Unit: a.Unit, From: a.From})
		}
	}
}

// user plans the account. It comes with the packages, before the builds
// that run as the user (and after the packages that bring its shell and
// groups).
func (p *Plan) user(in Input, u *machine.User) {
	want := in.Config.User
	if u == nil {
		p.add(&Action{Op: OpCreateUser, Phase: PhasePackages, User: want.Name, Shell: want.Shell, Names: want.Groups, Why: "new"})
		return
	}
	if want.Shell != "" && u.Shell != want.Shell {
		p.add(&Action{Op: OpSetShell, Phase: PhasePackages, User: want.Name, Shell: want.Shell, Why: u.Shell + " → " + want.Shell})
	}
	var missing []string
	for _, g := range want.Groups {
		if !slices.Contains(u.Groups, g) {
			missing = append(missing, g)
		}
	}
	if len(missing) > 0 {
		p.add(&Action{Op: OpAddGroups, Phase: PhasePackages, User: want.Name, Names: missing})
	}
}

func ownerOf(fi fs.FileInfo) (uid, gid int) {
	if st, ok := fi.Sys().(*syscall.Stat_t); ok {
		return int(st.Uid), int(st.Gid)
	}
	return -1, -1
}

func systemIDs(owner, group string) (uid, gid int) {
	uid, gid = -1, -1
	if u, err := user.Lookup(owner); err == nil {
		uid, _ = strconv.Atoi(u.Uid)
	}
	if group == "" {
		return uid, gid
	}
	if g, err := user.LookupGroup(group); err == nil {
		gid, _ = strconv.Atoi(g.Gid)
	}
	return uid, gid
}

// limine plans the merge of the hand-written part of /boot/limine.conf.
func (p *Plan) limine(in Input) error {
	if in.Config.Limine == "" {
		return nil
	}
	repo, err := os.ReadFile(in.Config.Limine)
	if err != nil {
		return err
	}
	a := &Action{Op: OpLimine, Phase: PhaseSystem, Value: string(repo), Hash: state.Hash(repo),
		HookKey: "limine.conf", From: "host " + in.Config.Host}
	live, err := os.ReadFile(in.Root + "/boot/limine.conf")
	switch {
	case errors.Is(err, fs.ErrNotExist):
		p.note("/boot/limine.conf does not exist: boot.limine is left for the installer")
		return nil
	case errors.Is(err, fs.ErrPermission):
		if in.System.Hooks[a.HookKey] == a.Hash {
			return nil
		}
		a.Why = "can't read /boot without root"
	case err != nil:
		return err
	default:
		merged := limine.Merge(string(repo), string(live))
		if limine.Same(merged, string(live)) {
			if in.System.Hooks[a.HookKey] != a.Hash {
				a.Op, a.Why = OpAdopt, "already matches"
				p.add(a)
			}
			return nil
		}
		a.Why, a.Old, a.Content = "differs", live, []byte(merged)
	}
	p.add(a)
	return nil
}

// Only keeps the system part (packages, AUR, system) or the home part.
func (p *Plan) Only(system bool) {
	p.Actions = slices.DeleteFunc(p.Actions, func(a *Action) bool { return (a.Phase == PhaseHome) == system })
}
