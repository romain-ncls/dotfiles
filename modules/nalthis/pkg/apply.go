package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

const schemeName = "Nalthis"

// repoDir is the dotfiles repo, found like lodestar: $LODESTAR_REPO, then ~/dotfiles.
func repoDir() (string, error) {
	if dir := os.Getenv("LODESTAR_REPO"); dir != "" {
		return dir, nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, "dotfiles"), nil
}

// The knobs live in the repo, so a change made with the sliders is a change
// to the dotfiles, never only on the machine.
func knobsPath() (string, error) {
	repo, err := repoDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(repo, "modules", "nalthis", "palette.json"), nil
}

func loadKnobs() (Knobs, error) {
	path, err := knobsPath()
	if err != nil {
		return Knobs{}, err
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, fs.ErrNotExist) {
		return Defaults, nil
	}
	if err != nil {
		return Knobs{}, err
	}
	k := Defaults
	if err := json.Unmarshal(data, &k); err != nil {
		return Knobs{}, fmt.Errorf("%s: %w", path, err)
	}
	k.Clamp()
	return k, nil
}

func saveKnobs(k Knobs) error {
	path, err := knobsPath()
	if err != nil {
		return err
	}
	data, err := json.MarshalIndent(k, "", "  ")
	if err != nil {
		return err
	}
	return writeAtomic(path, append(data, '\n'))
}

func configDir() (string, error) {
	if dir := os.Getenv("XDG_CONFIG_HOME"); dir != "" {
		return dir, nil
	}
	home, err := os.UserHomeDir()
	return filepath.Join(home, ".config"), err
}

func dataDir() (string, error) {
	if dir := os.Getenv("XDG_DATA_HOME"); dir != "" {
		return dir, nil
	}
	home, err := os.UserHomeDir()
	return filepath.Join(home, ".local", "share"), err
}

// apply makes the session use the knobs, live: it writes the scheme file
// (so the Colors page lists it), merges its color groups into kdeglobals and
// tells running apps the palette changed. plasma-apply-colorscheme can't do
// it: it refuses to re-apply the scheme that is already set.
func apply(k Knobs) error {
	scheme := Scheme(schemeName, k)
	data, err := dataDir()
	if err != nil {
		return err
	}
	var buf bytes.Buffer
	if err := writeINI(&buf, scheme); err != nil {
		return err
	}
	if err := writeAtomic(filepath.Join(data, "color-schemes", schemeName+".colors"), buf.Bytes()); err != nil {
		return err
	}
	// Konsole reads its own schemes; new tabs and windows take the change.
	if err := writeKonsoleSchemes(filepath.Join(data, "konsole"), k); err != nil {
		return err
	}

	cfg, err := configDir()
	if err != nil {
		return err
	}
	globals := filepath.Join(cfg, "kdeglobals")
	current, err := readINI(globals)
	if err != nil && !errors.Is(err, fs.ErrNotExist) {
		return err
	}
	buf.Reset()
	if err := writeINI(&buf, merge(current, scheme)); err != nil {
		return err
	}
	if err := writeAtomic(globals, buf.Bytes()); err != nil {
		return err
	}
	return notify(scheme)
}

// notify sends what KDE's own color scheme switch sends: KGlobalSettings'
// palette change (Qt apps) and kconfig's change notification for each group
// (Plasma, KWin, anything watching kdeglobals).
func notify(scheme []Group) error {
	busctl := func(args ...string) error {
		out, err := exec.Command("busctl", append([]string{"--user", "emit"}, args...)...).CombinedOutput()
		if err != nil {
			return fmt.Errorf("busctl %v: %v: %s", args, err, out)
		}
		return nil
	}
	// KConfig's signal is a{saay}: group -> changed key names as byte arrays
	// (recorded from plasma-apply-colorscheme with busctl monitor). It makes
	// apps re-read kdeglobals before they rebuild their palette. Nested
	// groups are written with \x1d between the names, as KConfig does.
	args := []string{"/kdeglobals", "org.kde.kconfig.notify", "ConfigChanged", "a{saay}", fmt.Sprint(len(scheme))}
	for _, g := range scheme {
		args = append(args, strings.ReplaceAll(g.Name, "][", "\x1d"), fmt.Sprint(len(g.Keys)))
		for _, kv := range g.Keys {
			args = append(args, fmt.Sprint(len(kv[0])))
			for _, b := range []byte(kv[0]) {
				args = append(args, fmt.Sprint(b))
			}
		}
	}
	if err := busctl(args...); err != nil {
		return err
	}
	// type 0 = PaletteChanged
	return busctl("/KGlobalSettings", "org.kde.KGlobalSettings", "notifyChange", "ii", "0", "0")
}

func writeAtomic(path string, data []byte) error {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	if _, err := tmp.Write(data); err != nil {
		tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	if info, err := os.Stat(path); err == nil {
		os.Chmod(tmp.Name(), info.Mode().Perm())
	} else {
		os.Chmod(tmp.Name(), 0o644)
	}
	return os.Rename(tmp.Name(), path)
}
