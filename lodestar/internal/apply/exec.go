// Package apply carries out a plan: the root phases in one process started
// through sudo, the others as the user.
package apply

import (
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"

	"github.com/romain-ncls/dotfiles/lodestar/internal/limine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

// env is what executing an action needs to know about where it runs.
type env struct {
	user  string       // the configured user
	repo  string       // the repo lodestar reads
	home  string       // the user's home
	root  string       // filesystem prefix, "" on a running system
	st    *state.State // updated as actions succeed
	out   io.Writer    // progress
	owner *account     // owner of home files when running as root
}

type account struct{ uid, gid int }

// systemdRunning tells whether units can be started now, or only linked:
// not under a root prefix, not in a chroot (an install), and systemd is PID 1.
func (e *env) systemdRunning() bool {
	if e.root != "" || inChroot() {
		return false
	}
	_, err := os.Stat("/run/systemd/system")
	return err == nil
}

// inChroot tells whether / is not PID 1's root.
func inChroot() bool {
	var self, init syscall.Stat_t
	if syscall.Stat("/", &self) != nil || syscall.Stat("/proc/1/root/.", &init) != nil {
		return false
	}
	return self.Dev != init.Dev || self.Ino != init.Ino
}

func (e *env) systemctl(args ...string) []string {
	if e.systemdRunning() {
		return append([]string{"systemctl"}, args...)
	}
	root := e.root
	if root == "" {
		root = "/"
	}
	return append([]string{"systemctl", "--root=" + root}, slices.DeleteFunc(args, func(a string) bool { return a == "--now" })...)
}

// do carries out one action and records it in the state.
func (e *env) do(a *plan.Action) error {
	switch a.Op {
	case plan.OpInstall:
		// No --asexplicit: it would mark the dependencies explicit too.
		return e.run(append([]string{"pacman", "-S", "--needed", "--noconfirm"}, a.Names...)...)
	case plan.OpAsExplicit:
		return e.run(append([]string{"pacman", "-D", "--asexplicit"}, a.Names...)...)
	case plan.OpInstallAUR:
		if err := e.bootstrapYay(); err != nil {
			return err
		}
		return e.asUser(true, append([]string{"yay", "-S", "--needed", "--noconfirm"}, a.Names...)...)
	case plan.OpBuild:
		return e.build(a)
	case plan.OpHook:
		return e.hook(a)
	case plan.OpJSON:
		return e.writeJSON(a)
	case plan.OpLimine:
		return e.limine(a)
	case plan.OpWrite, plan.OpLink:
		write := e.write
		if a.Op == plan.OpLink {
			write = e.link
		}
		err := write(a)
		if errors.Is(err, syscall.EBUSY) {
			// arch-chroot bind-mounts the live system's /etc/resolv.conf
			fmt.Fprintf(e.out, "    %s is a mount point here: left as it is (the installer writes it afterwards)\n", a.Display)
			return nil
		}
		if err != nil {
			return err
		}
		e.record(a)
	case plan.OpAdopt:
		e.record(a)
	case plan.OpForget:
		if a.KDEID != "" {
			delete(e.st.KDE, a.KDEID)
		} else {
			delete(e.st.Files, a.Path)
		}
	case plan.OpKDE:
		if err := e.kde(a); err != nil {
			return err
		}
		e.record(a)
	case plan.OpKDEList:
		if err := e.kdeList(a); err != nil {
			return err
		}
		e.record(a)
	case plan.OpRemove:
		if ok, err := e.unchanged(a); !ok || err != nil {
			return err
		}
		if err := os.Remove(e.root + a.Path); err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
		delete(e.st.Files, a.Path)
	case plan.OpRestoreOriginal:
		if ok, err := e.unchanged(a); !ok || err != nil {
			return err
		}
		if err := os.Rename(e.root+filepath.Join(state.OriginalsDir, a.Path), e.root+a.Path); err != nil {
			return err
		}
		delete(e.st.Files, a.Path)
	case plan.OpRestorePackage:
		if ok, err := e.unchanged(a); !ok || err != nil {
			return err
		}
		if err := e.restoreFromPackage(a); err != nil {
			return err
		}
		delete(e.st.Files, a.Path)
	case plan.OpRun:
		if a.LiveOnly && !e.systemdRunning() {
			fmt.Fprintln(e.out, "    skipped: nothing runs yet")
			return nil
		}
		return e.run("sh", "-c", a.Command)
	case plan.OpEnable, plan.OpDisable:
		verb := "enable"
		if a.Op == plan.OpDisable {
			verb = "disable"
		}
		args := []string{verb, "--now", a.Unit}
		key := "system:" + a.Unit
		if a.Global {
			args, key = []string{"--global", verb, a.Unit}, "global:"+a.Unit
		}
		if err := e.run(e.systemctl(args...)...); err != nil {
			return err
		}
		e.st.SetUnit(key, a.Op == plan.OpEnable)
	case plan.OpStartUser:
		if os.Getenv("XDG_RUNTIME_DIR") == "" {
			fmt.Fprintf(e.out, "    %s starts at the next login\n", a.Unit)
			return nil
		}
		if err := e.run("systemctl", "--user", "daemon-reload"); err != nil {
			return err
		}
		return e.run("systemctl", "--user", "start", a.Unit)
	case plan.OpCreateUser:
		args := []string{"useradd", "--create-home"}
		if e.root != "" {
			args = append(args, "--root", e.root)
		}
		if a.Shell != "" {
			args = append(args, "--shell", a.Shell)
		}
		if groups := e.existingGroups(a.Names); len(groups) > 0 {
			args = append(args, "--groups", strings.Join(groups, ","))
		}
		return e.run(append(args, a.User)...)
	case plan.OpSetShell:
		return e.run("usermod", "--shell", a.Shell, a.User)
	case plan.OpAddGroups:
		groups := e.existingGroups(a.Names)
		if len(groups) == 0 {
			return nil
		}
		return e.run("usermod", "--append", "--groups", strings.Join(groups, ","), a.User)
	default:
		return fmt.Errorf("unknown action %q", a.Op)
	}
	return nil
}

func (e *env) record(a *plan.Action) {
	switch {
	case a.HookKey != "":
		e.st.Hooks[a.HookKey] = a.Hash
		return
	case a.List != "":
		e.st.SetList(a.KDEFile, len(a.Entries) > 0)
		return
	case a.KDEID != "" && a.Delete:
		delete(e.st.KDE, a.KDEID)
		return
	case a.KDEID != "":
		e.st.KDE[a.KDEID] = state.KDEKey{File: a.KDEFile, Group: a.KDEGroup, Key: a.KDEKey, Value: a.Value}
		return
	}
	rec := a.Record
	if prev, ok := e.st.Files[a.Path]; ok && prev.Original {
		rec.Original = true
	}
	if a.Original {
		rec.Original = true
	}
	e.st.Files[a.Path] = rec
}

func (e *env) run(args ...string) error {
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, e.out, e.out
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("%s: %w", strings.Join(args, " "), err)
	}
	return nil
}

// existingGroups drops (with a warning) the groups that don't exist yet.
func (e *env) existingGroups(names []string) []string {
	var out []string
	for _, g := range names {
		if _, err := user.LookupGroup(g); err != nil {
			fmt.Fprintf(e.out, "    warning: group %s does not exist; the next apply adds it\n", g)
			continue
		}
		out = append(out, g)
	}
	return out
}

// unchanged tells whether the file is still what lodestar wrote, so that
// removing it loses nothing. It warns and returns false otherwise.
func (e *env) unchanged(a *plan.Action) (bool, error) {
	phys := e.root + a.Path
	if a.ExpectLink != "" {
		if cur, err := os.Readlink(phys); err != nil || cur != a.ExpectLink {
			fmt.Fprintf(e.out, "    %s changed since the plan: left as it is\n", a.Display)
			return false, nil
		}
		return true, nil
	}
	data, err := os.ReadFile(phys)
	if err != nil {
		return false, err
	}
	if a.ExpectHash != "" && state.Hash(data) != a.ExpectHash {
		fmt.Fprintf(e.out, "    %s changed since lodestar wrote it: left as it is\n", a.Display)
		delete(e.st.Files, a.Path)
		return false, nil
	}
	return true, nil
}

// write replaces the file atomically, after keeping the original if asked
// and running the check command on the new content.
func (e *env) write(a *plan.Action) error {
	phys := e.root + a.Path
	if err := e.keepOriginal(a); err != nil {
		return err
	}
	if err := e.mkdirs(filepath.Dir(phys)); err != nil {
		return err
	}
	tmp := filepath.Join(filepath.Dir(phys), "."+filepath.Base(phys)+".lodestar")
	if err := os.WriteFile(tmp, a.Content, a.Mode); err != nil {
		return err
	}
	defer os.Remove(tmp)                          // after a successful rename, there is nothing left to remove
	if err := os.Chmod(tmp, a.Mode); err != nil { // WriteFile's mode goes through the umask
		return err
	}
	if err := e.chown(tmp, a); err != nil {
		return err
	}
	if a.Check != "" {
		cmd := strings.ReplaceAll(a.Check, "{}", shellQuote(tmp))
		if err := e.run("sh", "-c", cmd); err != nil {
			return fmt.Errorf("the check failed, the file was not changed: %w", err)
		}
	}
	return os.Rename(tmp, phys)
}

func (e *env) link(a *plan.Action) error {
	phys := e.root + a.Path
	if err := e.keepOriginal(a); err != nil {
		return err
	}
	if err := e.mkdirs(filepath.Dir(phys)); err != nil {
		return err
	}
	tmp := filepath.Join(filepath.Dir(phys), "."+filepath.Base(phys)+".lodestar")
	os.Remove(tmp)
	if err := os.Symlink(a.LinkTo, tmp); err != nil {
		return err
	}
	if e.owner != nil && a.Phase == plan.PhaseHome {
		os.Lchown(tmp, e.owner.uid, e.owner.gid)
	}
	return os.Rename(tmp, phys)
}

// keepOriginal copies a file no package owns before lodestar first replaces it.
func (e *env) keepOriginal(a *plan.Action) error {
	if !a.Original {
		return nil
	}
	src := e.root + a.Path
	dst := e.root + filepath.Join(state.OriginalsDir, a.Path)
	if _, err := os.Lstat(dst); err == nil {
		return nil // kept on an earlier run
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o700); err != nil {
		return err
	}
	return e.run("cp", "-a", "--no-dereference", src, dst)
}

// mkdirs creates missing parents; in $HOME they belong to the user.
func (e *env) mkdirs(dir string) error {
	var missing []string
	for d := dir; ; d = filepath.Dir(d) {
		if _, err := os.Lstat(d); err == nil || d == "/" || d == "." {
			break
		}
		missing = append(missing, d)
	}
	// Folders made in $HOME are private, as gpg and ssh require for theirs.
	perm := fs.FileMode(0o755)
	if e.home != "" && strings.HasPrefix(dir+"/", e.root+e.home+"/") {
		perm = 0o700
	}
	if err := os.MkdirAll(dir, perm); err != nil {
		return err
	}
	if e.owner != nil {
		for _, d := range missing {
			if strings.HasPrefix(d, e.root+"/home/") {
				os.Chown(d, e.owner.uid, e.owner.gid)
			}
		}
	}
	return nil
}

func (e *env) chown(path string, a *plan.Action) error {
	if os.Geteuid() != 0 {
		return nil
	}
	if a.Phase == plan.PhaseHome {
		if e.owner != nil {
			return os.Chown(path, e.owner.uid, e.owner.gid)
		}
		return nil
	}
	uid, gid := 0, 0
	if a.Owner != "" && a.Owner != "root" {
		u, err := user.Lookup(a.Owner)
		if err != nil {
			return fmt.Errorf("%s: owner %s: %w", a.Display, a.Owner, err)
		}
		uid, _ = strconv.Atoi(u.Uid)
	}
	if a.Group != "" && a.Group != "root" {
		g, err := user.LookupGroup(a.Group)
		if err != nil {
			return fmt.Errorf("%s: group %s: %w", a.Display, a.Group, err)
		}
		gid, _ = strconv.Atoi(g.Gid)
	}
	return os.Chown(path, uid, gid)
}

// restoreFromPackage extracts the package's version of the file from the
// archive of the installed version: from pacman's cache, else from the repos
// if they still have that version, else from the Arch Linux Archive.
func (e *env) restoreFromPackage(a *plan.Action) error {
	info, err := exec.Command("pacman", "-Qi", a.Package).Output()
	if err != nil {
		return fmt.Errorf("pacman -Qi %s: %w", a.Package, err)
	}
	version, arch := field(info, "Version"), field(info, "Architecture")
	full := a.Package + "-" + version + "-" + arch
	find := func(dir string) string {
		matches, _ := filepath.Glob(filepath.Join(dir, full+".pkg.tar.*"))
		for _, m := range matches {
			if !strings.HasSuffix(m, ".sig") {
				return m
			}
		}
		return ""
	}
	cache := e.root + "/var/cache/pacman/pkg"
	archive := find(cache)
	if archive == "" {
		if repo, err := exec.Command("pacman", "-Si", a.Package).Output(); err == nil && field(repo, "Version") == version {
			if err := e.run("pacman", "-Sw", "--noconfirm", a.Package); err != nil {
				return err
			}
			archive = find(cache)
		}
	}
	tmp, err := os.MkdirTemp(filepath.Dir(e.root+a.Path), ".lodestar-restore")
	if err != nil {
		return err
	}
	defer os.RemoveAll(tmp)
	if archive == "" {
		url := fmt.Sprintf("https://archive.archlinux.org/packages/%c/%s/%s.pkg.tar.zst", a.Package[0], a.Package, full)
		archive = filepath.Join(tmp, full+".pkg.tar.zst")
		fmt.Fprintf(e.out, "    %s is no longer in the repos: downloading it from the Arch Linux Archive\n", full)
		if err := e.run("curl", "-fsSL", "-o", archive, url); err != nil {
			return fmt.Errorf("no archive of %s in the cache, the repos or the Arch Linux Archive", full)
		}
	}
	rel := strings.TrimPrefix(a.Path, "/")
	out := filepath.Join(tmp, "out")
	if err := os.Mkdir(out, 0o700); err != nil {
		return err
	}
	if err := e.run("bsdtar", "-xpf", archive, "-C", out, rel); err != nil {
		return err
	}
	return os.Rename(filepath.Join(out, rel), e.root+a.Path)
}

// field reads "Name : value" from pacman -Qi/-Si output.
func field(info []byte, name string) string {
	for _, line := range strings.Split(string(info), "\n") {
		k, v, ok := strings.Cut(line, ":")
		if ok && strings.TrimSpace(k) == name {
			return strings.TrimSpace(v)
		}
	}
	return ""
}

func shellQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }

// limine merges the repo's part into /boot/limine.conf, keeps the previous
// file as limine.conf.bak, and re-enrolls the config's hash.
func (e *env) limine(a *plan.Action) error {
	path := e.root + "/boot/limine.conf"
	live, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	merged := limine.Merge(a.Value, string(live))
	if merged != string(live) {
		if err := os.WriteFile(path+".bak", live, 0o600); err != nil {
			return err
		}
		if err := os.WriteFile(path, []byte(merged), 0o600); err != nil {
			return err
		}
		if _, err := exec.LookPath("limine-update"); err == nil && e.root == "" {
			if err := e.run("limine-update"); err != nil {
				return err
			}
		}
	}
	e.st.Hooks[a.HookKey] = a.Hash
	return nil
}
