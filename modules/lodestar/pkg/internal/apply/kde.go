package apply

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strconv"

	"github.com/romain-ncls/dotfiles/lodestar/internal/kconfig"
	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
)

// kdeDir is the user's ~/.config, under the root prefix.
func (e *env) kdeDir() string { return e.root + filepath.Join(e.home, ".config") }

// kde sets or deletes one key with kwriteconfig6, KDE's own writer.
func (e *env) kde(a *plan.Action) error {
	path := filepath.Join(e.kdeDir(), a.KDEFile)
	if err := e.mkdirs(filepath.Dir(path)); err != nil {
		return err
	}
	args := []string{"kwriteconfig6", "--file", path}
	for _, g := range a.KDEGroup {
		args = append(args, "--group", g)
	}
	args = append(args, "--key", a.KDEKey)
	if a.Delete {
		args = append(args, "--delete")
	} else {
		args = append(args, "--", a.Value)
	}
	if err := e.run(args...); err != nil {
		return err
	}
	return e.giveToUser(path)
}

var breezeGroup = regexp.MustCompile(`^Windeco Exception [0-9]+$`)

// kdeList rewrites an owned list, keeping the rest of the file.
func (e *env) kdeList(a *plan.Action) error {
	path := filepath.Join(e.kdeDir(), a.KDEFile)
	f, err := kconfig.Read(path)
	if err != nil {
		return err
	}
	switch a.List {
	case "breeze":
		f.DeleteGroups(func(p []string) bool { return len(p) == 1 && breezeGroup.MatchString(p[0]) })
		for i, entry := range a.Entries {
			f.SetGroup([]string{"Windeco Exception " + strconv.Itoa(i)}, entry)
		}
	case "kwinrules":
		// lodestar owns the whole file; only the migration markers stay.
		f.DeleteGroups(func(p []string) bool { return len(p) != 1 || p[0] != "$Version" })
		order := ""
		for i, entry := range a.Entries {
			name := strconv.Itoa(i + 1)
			f.SetGroup([]string{name}, entry)
			if order != "" {
				order += ","
			}
			order += name
		}
		if len(a.Entries) > 0 {
			f.SetGroup([]string{"General"}, map[string]string{"Order": order})
		}
	default:
		return fmt.Errorf("unknown KDE list %q", a.List)
	}
	if err := e.mkdirs(filepath.Dir(path)); err != nil {
		return err
	}
	tmp := path + ".lodestar"
	if err := os.WriteFile(tmp, f.Bytes(), 0o600); err != nil {
		return err
	}
	if err := os.Rename(tmp, path); err != nil {
		return err
	}
	return e.giveToUser(path)
}

// giveToUser hands a file written as root (install, container) to the user.
func (e *env) giveToUser(path string) error {
	if e.owner == nil {
		return nil
	}
	return os.Chown(path, e.owner.uid, e.owner.gid)
}
