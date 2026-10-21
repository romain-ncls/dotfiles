package drift

import (
	"os"
	"path/filepath"
	"slices"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

func TestFind(t *testing.T) {
	root := t.TempDir()
	for p, content := range map[string]string{
		"etc/declared.conf":                             "x",
		"etc/owned.conf":                                "x",
		"etc/by-hand.conf":                              "x",
		"etc/ignored/deep/file":                         "x",
		"etc/machine-id":                                "x",
		"usr/lib/systemd/system/resolved.service":       "[Install]\nAlso=resolved-varlink.socket\n",
		"etc/systemd/system/multi-user.target.wants/.k": "",
	} {
		full := filepath.Join(root, p)
		os.MkdirAll(filepath.Dir(full), 0o755)
		os.WriteFile(full, []byte(content), 0o644)
	}
	os.Symlink("/usr/lib/systemd/system/x.service", filepath.Join(root, "etc/systemd/system/multi-user.target.wants/x.service"))

	c := &config.Config{
		Packages:      []config.Item{{Name: "base"}},
		LocalPackages: []config.LocalPackage{{Names: []string{"mytool"}}},
		Services:      []config.Item{{Name: "resolved.service"}},
		User:          config.User{Name: "romain", Groups: []string{"wheel"}},
		Ignore:        []string{"/etc/ignored/*"},
	}
	m := &machine.Fake{
		Installed: map[string]machine.Package{
			"base":   {Explicit: true},
			"mytool": {Explicit: true},
			"htop":   {Explicit: true}, // installed by hand
			"glibc":  {},               // a dependency
		},
		Owned: map[string]bool{"/etc/owned.conf": true},
		Backup: []machine.Backup{
			{Path: "/etc/owned.conf", Package: "foo", Status: "modified"},
			{Path: "/etc/declared.conf", Package: "bar", Status: "modified"}, // declared: fine
			{Path: "/etc/sudoers", Package: "sudo", Status: "UNREADABLE"},
		},
		System: map[string]machine.Unit{
			"resolved.service":        {State: "enabled", Preset: "disabled"},
			"resolved-varlink.socket": {State: "enabled", Preset: "disabled"}, // Also= of a declared unit
			"getty@.service":          {State: "enabled", Preset: "enabled"},  // by preset
			"sshd.service":            {State: "enabled", Preset: "disabled"}, // by hand
		},
		Global: map[string]machine.Unit{},
		Users:  map[string]*machine.User{"romain": {Groups: []string{"romain", "wheel", "video"}, PrimaryGroup: "romain"}},
	}
	p := &plan.Plan{Desired: map[string]state.File{"/etc/declared.conf": {}}, LocalNames: []string{"mytool"}}

	r, err := Find(c, m, p, root)
	if err != nil {
		t.Fatal(err)
	}
	for name, check := range map[string]struct{ got, want []string }{
		"packages": {r.UndeclaredPackages, []string{"htop"}},
		"unowned":  {r.UnownedFiles, []string{"/etc/by-hand.conf", "/etc/systemd/system/multi-user.target.wants/.k"}},
		"units":    {r.Units, []string{"sshd.service"}},
		"groups":   {r.ExtraGroups, []string{"video"}},
		"unread":   {r.Unreadable, []string{"/etc/sudoers"}},
	} {
		if !slices.Equal(check.got, check.want) {
			t.Errorf("%s = %q, want %q", name, check.got, check.want)
		}
	}
	if len(r.ModifiedFiles) != 1 || r.ModifiedFiles[0].Path != "/etc/owned.conf" {
		t.Errorf("modified = %+v", r.ModifiedFiles)
	}
}
