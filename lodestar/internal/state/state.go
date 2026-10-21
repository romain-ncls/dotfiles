// Package state records what lodestar wrote, so it can remove what the repo
// no longer declares and tell edits on the machine from changes in the repo.
package state

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
)

// SystemPath and HomePath are where the two state files live; HomePath is
// relative to the user's home.
const (
	SystemPath    = "/var/lib/lodestar/state.json"
	OriginalsDir  = "/var/lib/lodestar/originals"
	HomePath      = ".local/state/lodestar/state.json"
	stateFileMode = 0o644
)

// State is one state file.
type State struct {
	Files map[string]File `json:"files"`
	// Units lodestar enabled: "system:foo.service" or "global:bar.service".
	Units []string `json:"units,omitempty"`
	// KDE keys lodestar set, by file/group/key.
	KDE map[string]KDEKey `json:"kde,omitempty"`
	// KDE lists lodestar owns: "breezerc", "kwinrulesrc".
	Lists []string `json:"lists,omitempty"`
	// Hashes of hooks (by module and command) and local packages (by name)
	// at their last successful run or build.
	Hooks    map[string]string `json:"hooks,omitempty"`
	Packages map[string]Built  `json:"packages,omitempty"`
}

// KDEKey is a KDE key lodestar set.
type KDEKey struct {
	File  string   `json:"file"`
	Group []string `json:"group"`
	Key   string   `json:"key"`
	Value string   `json:"value"`
}

// Built is a local package lodestar built.
type Built struct {
	Hash  string   `json:"hash"`
	Names []string `json:"names"`
}

// File is a file or link lodestar wrote.
type File struct {
	Hash string `json:"hash,omitempty"` // of the content lodestar wrote
	Link string `json:"link,omitempty"` // or the link's target
	From string `json:"from"`
	// Original: lodestar replaced a file no package owns, and kept it in
	// OriginalsDir to put it back when the repo drops the file.
	Original bool `json:"original,omitempty"`
}

// Load reads a state file; a missing one is an empty state.
func Load(path string) (*State, error) {
	s := &State{}
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		s.init()
		return s, nil
	}
	if err != nil {
		return nil, err
	}
	if err := json.Unmarshal(data, s); err != nil {
		return nil, err
	}
	s.init()
	return s, nil
}

// Save writes the state file atomically.
func (s *State) Save(path string) error {
	sort.Strings(s.Units)
	data, err := json.MarshalIndent(s, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp := path + ".new"
	if err := os.WriteFile(tmp, append(data, '\n'), stateFileMode); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

// HasUnit tells whether lodestar enabled the unit.
func (s *State) HasUnit(key string) bool {
	for _, u := range s.Units {
		if u == key {
			return true
		}
	}
	return false
}

// SetUnit records or forgets a unit lodestar enabled.
func (s *State) SetUnit(key string, enabled bool) {
	out := s.Units[:0]
	for _, u := range s.Units {
		if u != key {
			out = append(out, u)
		}
	}
	if enabled {
		out = append(out, key)
	}
	s.Units = out
}

// Hash is the hash recorded for file contents.
func Hash(content []byte) string {
	sum := sha256.Sum256(content)
	return hex.EncodeToString(sum[:])
}

// New returns an empty state.
func New() *State {
	s := &State{}
	s.init()
	return s
}

func (s *State) init() {
	if s.Files == nil {
		s.Files = map[string]File{}
	}
	if s.KDE == nil {
		s.KDE = map[string]KDEKey{}
	}
	if s.Hooks == nil {
		s.Hooks = map[string]string{}
	}
	if s.Packages == nil {
		s.Packages = map[string]Built{}
	}
}

// OwnsList tells whether lodestar owns a KDE list.
func (s *State) OwnsList(file string) bool {
	for _, l := range s.Lists {
		if l == file {
			return true
		}
	}
	return false
}

// SetList records whether lodestar owns a KDE list.
func (s *State) SetList(file string, owned bool) {
	out := s.Lists[:0]
	for _, l := range s.Lists {
		if l != file {
			out = append(out, l)
		}
	}
	if owned {
		out = append(out, file)
	}
	s.Lists = out
}
