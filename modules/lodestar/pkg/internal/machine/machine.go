// Package machine reads what is installed and enabled, through pacman,
// systemctl and getent. Nothing here needs root.
package machine

import (
	"bufio"
	"bytes"
	"errors"
	"fmt"
	"os/exec"
	"strings"
)

// Package is an installed package.
type Package struct {
	Name     string
	Version  string
	Explicit bool // installed explicitly, not as a dependency
}

// Unit is a unit file and its state, as systemctl list-unit-files shows it.
type Unit struct {
	State  string // enabled, disabled, static, alias, masked, …
	Preset string // enabled or disabled by the distribution's preset
}

// User is a login user.
type User struct {
	Home         string
	Shell        string
	Groups       []string
	PrimaryGroup string
}

// Backup is a package's config file (pacman's backup array) and whether it
// differs from the package's version.
type Backup struct {
	Path, Package string
	Status        string // modified, unmodified, or UNREADABLE without root
}

// Machine reads the machine's packages, units and users.
type Machine interface {
	Packages() (map[string]Package, error)
	// InRepos lists the names in the sync databases.
	InRepos() (map[string]bool, error)
	// Owner returns the package owning path, or "".
	Owner(path string) (string, error)
	// Units returns the system units, or the global user units.
	Units(global bool) (map[string]Unit, error)
	// User returns nil when the user does not exist.
	User(name string) (*User, error)
	GroupExists(name string) (bool, error)
	// OwnedFiles is every path some package owns.
	OwnedFiles() (map[string]bool, error)
	// Backups lists every package's config files and their status.
	Backups() ([]Backup, error)
}

// Local reads the machine lodestar runs on.
type Local struct{}

func (Local) Packages() (map[string]Package, error) {
	out, err := run("pacman", "-Q")
	if err != nil {
		return nil, err
	}
	pkgs := map[string]Package{}
	for _, line := range lines(out) {
		name, version, _ := strings.Cut(line, " ")
		pkgs[name] = Package{Name: name, Version: version}
	}
	out, err = run("pacman", "-Qqe")
	if err != nil && len(out) > 0 {
		return nil, err
	}
	for _, name := range lines(out) {
		p := pkgs[name]
		p.Explicit = true
		pkgs[name] = p
	}
	return pkgs, nil
}

func (Local) InRepos() (map[string]bool, error) {
	out, err := run("pacman", "-Slq")
	if err != nil {
		return nil, err
	}
	names := map[string]bool{}
	for _, n := range lines(out) {
		names[n] = true
	}
	return names, nil
}

func (Local) Owner(path string) (string, error) {
	out, err := run("pacman", "-Qoq", path)
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) {
			return "", nil // "No package owns …"
		}
		return "", err
	}
	return strings.TrimSpace(string(out)), nil
}

func (Local) Units(global bool) (map[string]Unit, error) {
	args := []string{"list-unit-files", "--no-legend", "--no-pager", "--full"}
	if global {
		args = append([]string{"--global"}, args...)
	}
	out, err := run("systemctl", args...)
	if err != nil {
		return nil, err
	}
	units := map[string]Unit{}
	for _, line := range lines(out) {
		f := strings.Fields(line)
		if len(f) < 2 {
			continue
		}
		u := Unit{State: f[1]}
		if len(f) > 2 {
			u.Preset = f[2]
		}
		units[f[0]] = u
	}
	return units, nil
}

func (Local) User(name string) (*User, error) {
	out, err := run("getent", "passwd", name)
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && ee.ExitCode() == 2 {
			return nil, nil
		}
		return nil, err
	}
	f := strings.Split(strings.TrimSpace(string(out)), ":")
	if len(f) < 7 {
		return nil, fmt.Errorf("getent passwd %s: unexpected %q", name, out)
	}
	groups, err := run("id", "-Gn", name)
	if err != nil {
		return nil, err
	}
	primary, err := run("id", "-gn", name)
	if err != nil {
		return nil, err
	}
	return &User{Home: f[5], Shell: f[6], Groups: strings.Fields(string(groups)), PrimaryGroup: strings.TrimSpace(string(primary))}, nil
}

func (Local) OwnedFiles() (map[string]bool, error) {
	out, err := run("pacman", "-Qlq")
	if err != nil {
		return nil, err
	}
	owned := map[string]bool{}
	for _, p := range lines(out) {
		owned[strings.TrimSuffix(p, "/")] = true
	}
	return owned, nil
}

// Backups parses the "Backup Files" of pacman -Qii:
//
//	Name            : pacman
//	Backup Files    : /etc/pacman.conf [modified]
//	                  /etc/makepkg.conf [unmodified]
func (Local) Backups() ([]Backup, error) {
	out, err := run("pacman", "-Qii")
	if err != nil {
		return nil, err
	}
	var backups []Backup
	var pkg string
	inBackup := false
	for _, line := range strings.Split(string(out), "\n") {
		if k, v, ok := strings.Cut(line, " : "); ok && !strings.HasPrefix(line, " ") {
			switch strings.TrimSpace(k) {
			case "Name":
				pkg = strings.TrimSpace(v)
			case "Backup Files":
				inBackup = true
				line = v
			default:
				inBackup = false
			}
		}
		if !inBackup {
			continue
		}
		path, status, ok := strings.Cut(strings.TrimSpace(line), " [")
		if ok && strings.HasPrefix(path, "/") {
			backups = append(backups, Backup{Path: path, Package: pkg, Status: strings.TrimSuffix(status, "]")})
		}
	}
	return backups, nil
}

func (Local) GroupExists(name string) (bool, error) {
	_, err := run("getent", "group", name)
	if err != nil {
		var ee *exec.ExitError
		if errors.As(err, &ee) && ee.ExitCode() == 2 {
			return false, nil
		}
		return false, err
	}
	return true, nil
}

func run(name string, args ...string) ([]byte, error) {
	var stderr bytes.Buffer
	cmd := exec.Command(name, args...)
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		if stderr.Len() > 0 {
			return out, fmt.Errorf("%s %s: %s: %w", name, strings.Join(args, " "), strings.TrimSpace(stderr.String()), err)
		}
		return out, fmt.Errorf("%s %s: %w", name, strings.Join(args, " "), err)
	}
	return out, nil
}

func lines(b []byte) []string {
	var out []string
	sc := bufio.NewScanner(bytes.NewReader(b))
	sc.Buffer(make([]byte, 1<<20), 1<<20)
	for sc.Scan() {
		if l := strings.TrimSpace(sc.Text()); l != "" {
			out = append(out, l)
		}
	}
	return out
}
