package plan

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

func write(t *testing.T, root string, files map[string]string) {
	t.Helper()
	for p, content := range files {
		full := filepath.Join(root, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(full, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
}

// setup returns a repo, a machine root with /home/romain, and a fake machine.
func setup(t *testing.T, repo map[string]string) (*config.Config, string, *machine.Fake) {
	t.Helper()
	repoDir, root := t.TempDir(), t.TempDir()
	write(t, repoDir, repo)
	c, err := config.Load(repoDir, "box")
	if err != nil {
		t.Fatal(err)
	}
	os.MkdirAll(filepath.Join(root, "home/romain"), 0o755)
	m := &machine.Fake{
		Installed: map[string]machine.Package{"base": {Name: "base", Explicit: true}, "git": {Name: "git"}},
		Repos:     map[string]bool{"base": true, "git": true, "htop": true},
		Owners:    map[string]string{},
		System:    map[string]machine.Unit{"bluetooth.service": {State: "disabled"}, "fstrim.timer": {State: "enabled"}},
		Global:    map[string]machine.Unit{},
		Users:     map[string]*machine.User{"romain": {Home: "/home/romain", Shell: "/bin/bash", Groups: []string{"romain", "wheel"}}},
		Groups:    map[string]bool{"wheel": true, "docker": true},
	}
	return c, root, m
}

func compute(t *testing.T, c *config.Config, root string, m *machine.Fake, sys, home *state.State) *Plan {
	t.Helper()
	if sys == nil {
		sys = state.New()
	}
	if home == nil {
		home = state.New()
	}
	p, err := Compute(Input{Config: c, Machine: m, Root: root, System: sys, HomeSt: home, IDs: testIDs})
	if err != nil {
		t.Fatal(err)
	}
	return p
}

// testIDs makes every account the test's own, since the test owns every file
// of its machine root.
func testIDs(string, string) (int, int) { return os.Getuid(), os.Getgid() }

// summary is one line per action: "op target why".
func summary(p *Plan) []string {
	var out []string
	for _, a := range p.Actions {
		target := a.Display
		switch {
		case len(a.Names) > 0:
			target = strings.Join(a.Names, ",")
		case a.Unit != "":
			target = a.Unit
		case a.Command != "":
			target = a.Command
		case a.User != "" && target == "":
			target = a.User
		}
		out = append(out, strings.TrimSpace(fmt.Sprintf("%s %s %s", a.Op, target, a.Why)))
	}
	return out
}

const host = `
modules:
  - base
user:
  name: romain
  shell: /usr/bin/fish
  groups:
    - wheel
    - docker
vars:
  email: me@example.com
`

func TestPlanFreshMachine(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml": host,
		"modules/base/module.yaml": `
packages:
  - base
  - git
  - htop
  - yay-bin
services:
  - bluetooth.service
  - fstrim.timer
`,
		"modules/base/system/etc/locale.gen":    "en_US.UTF-8 UTF-8\n",
		"modules/base/system/etc/hostname":      "box\n",
		"modules/base/home/.gitconfig.tmpl":     "email = {{ .vars.email }}\n",
		"modules/base/home/.config/fish/a.fish": "set x 1\n",
	})
	write(t, root, map[string]string{"etc/hostname": "box\n"}) // already right
	p := compute(t, c, root, m, nil, nil)

	want := []string{
		"install htop",
		"explicit git installed as a dependency, now declared",
		"shell romain /bin/bash → /usr/bin/fish",
		"groups docker",
		"install-aur yay-bin",
		"adopt /etc/hostname already matches",
		"write /etc/locale.gen new",
		"run locale-gen after /etc/locale.gen",
		"enable bluetooth.service",
		"write ~/.config/fish/a.fish new",
		"write ~/.gitconfig new",
	}
	if got := summary(p); !slices.Equal(got, want) {
		t.Errorf("plan:\n  %s\nwant:\n  %s", strings.Join(got, "\n  "), strings.Join(want, "\n  "))
	}
	for _, a := range p.Actions {
		if a.Display == "~/.gitconfig" && string(a.Content) != "email = me@example.com\n" {
			t.Errorf("template rendered as %q", a.Content)
		}
	}
}

func TestPlanChangesAndRemovals(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml": `
modules:
  - base
user:
  name: romain
`,
		"modules/base/module.yaml":              "files:\n  /etc/sudoers:\n    mode: 0440\n",
		"modules/base/system/etc/sudoers":       "new\n",
		"modules/base/system/etc/vconsole.conf": "KEYMAP=fr\n",
	})
	write(t, root, map[string]string{
		"etc/sudoers":          "old\n",
		"etc/vconsole.conf":    "KEYMAP=fr\n", // right content, wrong mode below
		"etc/pacman.conf":      "lodestar wrote this\n",
		"etc/old.conf":         "lodestar wrote this\n",
		"home/romain/.edited":  "changed by hand\n",
		"home/romain/.dropped": "lodestar wrote this\n",
	})
	os.Chmod(filepath.Join(root, "etc/vconsole.conf"), 0o600)
	m.Owners["/etc/pacman.conf"] = "pacman"
	ours := state.Hash([]byte("lodestar wrote this\n"))
	sys := &state.State{Files: map[string]state.File{
		"/etc/pacman.conf": {Hash: ours, From: "base"},
		"/etc/old.conf":    {Hash: ours, From: "base"},
		"/etc/gone.conf":   {Hash: ours, From: "base"}, // already removed by hand
	}}
	home := &state.State{Files: map[string]state.File{
		"/home/romain/.edited":  {Hash: ours, From: "base"},
		"/home/romain/.dropped": {Hash: ours, From: "base"},
	}}
	p := compute(t, c, root, m, sys, home)

	want := []string{
		"write /etc/sudoers content",
		"write /etc/vconsole.conf mode 0600 → 0644",
		"remove /etc/old.conf no longer declared",
		"restore-package /etc/pacman.conf no longer declared: pacman's version comes back",
		"remove ~/.dropped no longer declared",
		"forget ~/.edited no longer declared, but changed on the machine since lodestar wrote it: left as it is",
	}
	if got := summary(p); !slices.Equal(got, want) {
		t.Errorf("plan:\n  %s\nwant:\n  %s", strings.Join(got, "\n  "), strings.Join(want, "\n  "))
	}
	for _, a := range p.Actions {
		if a.Display == "/etc/sudoers" && (a.Mode != 0o440 || string(a.Old) != "old\n") {
			t.Errorf("sudoers action = mode %o old %q", a.Mode, a.Old)
		}
	}
}

func TestPlanRefusals(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml":           "modules:\n  - base\nuser:\n  name: romain\n",
		"modules/base/module.yaml":      "services:\n  - masked.service\n  - static.service\n",
		"modules/base/home/.config/mpv": "",
	})
	os.MkdirAll(filepath.Join(root, "home/romain/.config/mpv"), 0o755)
	m.System["masked.service"] = machine.Unit{State: "masked"}
	m.System["static.service"] = machine.Unit{State: "static"}
	_, err := Compute(Input{Config: c, Machine: m, Root: root, System: state.New(), HomeSt: state.New()})
	if err == nil {
		t.Fatal("expected errors")
	}
	for _, want := range []string{"is masked", "is static", "is a directory"} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("error %q does not mention %q", err, want)
		}
	}
}
