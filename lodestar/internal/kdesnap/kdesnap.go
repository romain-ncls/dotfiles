// Package kdesnap takes snapshots of the KDE config files, to tell which
// keys changed since lodestar last applied (kde review) or during one change
// in System Settings (kde watch).
package kdesnap

import (
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/kconfig"
)

// Path is where the snapshot lives, relative to the user's home.
const Path = ".local/state/lodestar/kde.json"

// Snapshot is every key of every KDE file: file -> "group/…/key" -> value,
// as written in the file (escaped, so binary values survive JSON).
type Snapshot map[string]map[string]string

// Take reads the KDE files of a config dir (~/.config): every *rc file and
// kdeglobals.
func Take(configDir string) (Snapshot, error) {
	files, err := filepath.Glob(filepath.Join(configDir, "*rc"))
	if err != nil {
		return nil, err
	}
	files = append(files, filepath.Join(configDir, "kdeglobals"))
	s := Snapshot{}
	for _, p := range files {
		data, err := os.ReadFile(p)
		if err != nil {
			continue // gone, or not ours to read
		}
		s[filepath.Base(p)] = kconfig.Parse(data).RawEntries()
	}
	return s, nil
}

// Load reads a saved snapshot; nil when there is none yet.
func Load(path string) (Snapshot, error) {
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var s Snapshot
	return s, json.Unmarshal(data, &s)
}

// Save writes the snapshot.
func (s Snapshot) Save(path string) error {
	data, err := json.Marshal(s)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".new"
	if err := os.WriteFile(tmp, data, 0o600); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// Set records one key's value in the snapshot (or its absence).
func (s Snapshot) Set(file, key string, value *string) {
	if value == nil {
		delete(s[file], key)
		return
	}
	if s[file] == nil {
		s[file] = map[string]string{}
	}
	s[file][key] = *value
}

// Change is one key that differs between two snapshots. Values are as
// written in the file; Value unescapes them.
type Change struct {
	File string
	Key  string  // group/…/key
	Old  *string // nil: added
	New  *string // nil: removed
}

// Value unescapes a raw value of a change (nil stays nil).
func Value(raw *string) *string {
	if raw == nil {
		return nil
	}
	v := kconfig.Unescape(*raw)
	return &v
}

// Binary tells whether the change is a binary blob (a Qt window or
// splitter state, written as \x escapes): KDE state, never a setting.
func (c Change) Binary() bool {
	return (c.Old != nil && strings.Contains(*c.Old, `\x00`)) || (c.New != nil && strings.Contains(*c.New, `\x00`))
}

// ID is file/group/…/key.
func (c Change) ID() string { return c.File + "/" + c.Key }

// GroupAndKey splits the key into its groups and its name.
func (c Change) GroupAndKey() ([]string, string) {
	parts := strings.Split(c.Key, "/")
	return parts[:len(parts)-1], parts[len(parts)-1]
}

// Diff lists the keys that differ from before to after, sorted.
func Diff(before, after Snapshot) []Change {
	var out []Change
	files := map[string]bool{}
	for f := range before {
		files[f] = true
	}
	for f := range after {
		files[f] = true
	}
	for f := range files {
		b, a := before[f], after[f]
		for k, old := range b {
			if nv, ok := a[k]; !ok {
				out = append(out, Change{File: f, Key: k, Old: ptr(old)})
			} else if nv != old {
				out = append(out, Change{File: f, Key: k, Old: ptr(old), New: ptr(nv)})
			}
		}
		for k, nv := range a {
			if _, ok := b[k]; !ok {
				out = append(out, Change{File: f, Key: k, New: ptr(nv)})
			}
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].ID() < out[j].ID() })
	return out
}

func ptr(s string) *string { return &s }

// State lists keys KDE writes as it runs (window sizes, recent files, tiling
// layouts, migration markers…) as file/group/key globs where * also matches
// /. kde review never shows them. To be tuned as noise shows up.
var State = []string{
	"kconf_updaterc/*",
	"*/$Version/*",
	"plasma-org.kde.plasma.desktop-appletsrc/*",
	"plasmashellrc/PlasmaViews/*",
	"plasmashellrc/PlasmaTransientsConfig/*",
	"kwinrc/Tiling/*",
	"kactivitymanagerd-statsrc/*",
	"kactivitymanagerd-switcher/*",
	"bluedevilglobalrc/*",
	"systemsettingsrc/*",
	"*/MainWindow/*",
	"*/KFileDialog Settings/*",
	"*/FileDialogSize/*",
	"*/Recent*",
	"*/recent*",
	"*History*",
	"*/history",
	"*/State",
	"*/UiState*",
	"*HeaderState*",
	"*SplitterState*",
	"*Geometry*",
	"* Width *",
	"* Height *",
	"*/WindowState*",
	"*Timestamp*",
	"*/_k_friendly_name",
	"*/Seen",
	"*/dbVersion",
	"spectaclerc/Annotations/*",
	"spectaclerc/GuiConfig/*",
	"ksmserverrc/Session*",
	"ksmserverrc/LegacySession*",
	"ksmserverrc/Saved*",
}
