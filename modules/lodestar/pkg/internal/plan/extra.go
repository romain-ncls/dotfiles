package plan

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"regexp"
	"sort"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/dirhash"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
)

// json plans the JSON files that get keys merged into them.
func (p *Plan) json(in Input) error {
	for _, t := range in.Config.JSON {
		path := p.Abs(t.Path)
		desired := map[string]any{}
		for _, src := range t.Sources {
			obj, err := readJSONObject(src)
			if err != nil {
				return err
			}
			merge(desired, obj)
		}
		old, err := os.ReadFile(in.Root + path)
		if err != nil && !errors.Is(err, fs.ErrNotExist) {
			return err
		}
		live := map[string]any{}
		if len(bytes.TrimSpace(old)) > 0 {
			if err := json.Unmarshal(old, &live); err != nil {
				return fmt.Errorf("%s: not a JSON object: %w", t.Path, err)
			}
		}
		changed := differing(live, desired, "")
		if len(changed) == 0 {
			continue
		}
		if t.UnlessRunning != "" && in.Root == "" && running(t.UnlessRunning) {
			p.note("%s: %d keys wait until %s is closed (it would overwrite them on exit); apply again then", t.Path, len(changed), t.UnlessRunning)
			continue
		}
		merged := map[string]any{}
		merge(merged, live)
		merge(merged, desired)
		content, err := json.MarshalIndent(merged, "", "  ")
		if err != nil {
			return err
		}
		why := strings.Join(changed, ", ")
		if len(changed) > 4 {
			why = strings.Join(changed[:4], ", ") + fmt.Sprintf(" and %d more", len(changed)-4)
		}
		a := &Action{Op: OpJSON, Phase: PhaseHome, Path: path, Display: t.Path, Content: append(content, '\n'),
			Why: why, From: t.From}
		if old != nil {
			// Shown as a diff: formatted like Content, so that only the keys
			// that change show, not the app's own layout of the file.
			a.Old = old
			if live, err := json.MarshalIndent(live, "", "  "); err == nil {
				a.Old = append(live, '\n')
			}
		}
		p.add(a)
	}
	return nil
}

func readJSONObject(path string) (map[string]any, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	obj := map[string]any{}
	if err := json.Unmarshal(data, &obj); err != nil {
		return nil, fmt.Errorf("%s: not a JSON object: %w", path, err)
	}
	return obj, nil
}

// merge copies src into dst; objects merge key by key, anything else
// replaces.
func merge(dst, src map[string]any) {
	for k, v := range src {
		if sv, ok := v.(map[string]any); ok {
			dv, ok := dst[k].(map[string]any)
			if !ok {
				dv = map[string]any{}
				dst[k] = dv
			}
			merge(dv, sv)
			continue
		}
		dst[k] = v
	}
}

// differing lists the dotted paths of want whose value differs in have.
func differing(have, want map[string]any, prefix string) []string {
	var out []string
	for k, wv := range want {
		path := prefix + k
		if wm, ok := wv.(map[string]any); ok {
			hm, _ := have[k].(map[string]any)
			if hm == nil {
				hm = map[string]any{}
			}
			out = append(out, differing(hm, wm, path+".")...)
			continue
		}
		if hv, ok := have[k]; !ok || !reflect.DeepEqual(hv, wv) {
			out = append(out, path)
		}
	}
	sort.Strings(out)
	return out
}

// running tells whether a process with this name (its comm) runs.
func running(name string) bool {
	comms, _ := filepath.Glob("/proc/[0-9]*/comm")
	for _, c := range comms {
		if data, err := os.ReadFile(c); err == nil && strings.TrimSpace(string(data)) == name {
			return true
		}
	}
	return false
}

// hooks plans the hooks: always, or when their folder changed.
func (p *Plan) hooks(in Input) error {
	for _, h := range in.Config.Hooks {
		phase, st := PhaseHome, in.HomeSt
		if h.As == "root" {
			phase, st = PhaseSystem, in.System
		}
		key := h.From + ": " + h.Run
		a := &Action{Op: OpHook, Phase: phase, Command: h.Run, Dir: h.Dir, HookKey: key, From: h.From,
			Module: strings.TrimPrefix(h.From, "host "), User: ""}
		if h.When == "always" {
			a.Always, a.Why = true, "runs on every apply"
			p.add(a)
			continue
		}
		hash, err := dirhash.Sum([]string{h.Dir}, h.Run, h.As)
		if err != nil {
			return err
		}
		if st.Hooks[key] == hash {
			continue
		}
		a.Hash, a.Why = hash, "the module changed"
		if _, ran := st.Hooks[key]; !ran {
			a.Why = "first run"
		}
		p.add(a)
	}
	return nil
}

var commitRE = regexp.MustCompile(`^[0-9a-f]{40}$`)

// localPackages plans the builds of the local packages.
func (p *Plan) localPackages(in Input, installed map[string]machine.Package) error {
	for _, lp := range in.Config.LocalPackages {
		built := in.HomeSt.Packages[lp.Module]
		names := lp.Names
		if len(names) == 0 {
			names = built.Names
		}
		p.LocalNames = append(p.LocalNames, names...)
		a := &Action{Op: OpBuild, Phase: PhaseAUR, Module: lp.Module, From: lp.From, Names: names}
		var hash string
		var err error
		switch {
		case lp.Git == "":
			a.Dir = lp.Dir
			hash, err = dirhash.Sum(append([]string{lp.Dir}, lp.Watch...))
		case strings.HasPrefix(lp.Git, "~/") || strings.HasPrefix(lp.Git, "/"):
			checkout := p.Abs(lp.Git)
			a.Dir = filepath.Join(checkout, lp.Path)
			hash, err = worktreeHash(checkout, lp.Path)
		default:
			a.Git, a.Ref, a.PkgPath = lp.Git, lp.Ref, lp.Path
			if commitRE.MatchString(lp.Ref) {
				a.Commit = lp.Ref
			} else if in.Offline {
				p.note("%s: not checked (offline)", lp.Module)
				continue
			} else if a.Commit, err = resolveRef(lp.Git, lp.Ref); err != nil {
				p.note("%s: can't reach %s (%v): not built this time", lp.Module, lp.Git, err)
				continue
			}
			hash = a.Commit + ":" + lp.Path
		}
		if err != nil {
			return fmt.Errorf("%s: %w", lp.From, err)
		}
		a.Hash = hash

		missing := len(names) == 0
		rebuild := false
		for _, n := range names {
			if _, ok := installed[n]; !ok {
				missing = true
			}
			rebuild = rebuild || in.Rebuild[n]
		}
		switch {
		case missing:
			a.Why = "not installed"
		case rebuild:
			a.Why = "a library it uses changed"
		case built.Hash == "":
			a.Why = "installed, but not built by lodestar"
		case built.Hash != hash:
			a.Why = "changed"
			if a.Commit != "" {
				a.Why = "now at " + a.Commit[:12]
			}
		default:
			continue
		}
		p.add(a)
	}
	sort.Strings(p.LocalNames)
	return nil
}

// resolveRef finds the commit of a branch or tag with git ls-remote; an
// annotated tag gives its peeled commit.
func resolveRef(url, ref string) (string, error) {
	out, err := exec.Command("git", "ls-remote", url, ref, ref+"^{}").Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok && len(ee.Stderr) > 0 {
			return "", errors.New(strings.TrimSpace(string(ee.Stderr)))
		}
		return "", err
	}
	commit := ""
	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		hash, name, ok := strings.Cut(line, "\t")
		if !ok {
			continue
		}
		if strings.HasSuffix(name, "^{}") || commit == "" {
			commit = hash
		}
	}
	if commit == "" {
		return "", fmt.Errorf("no ref %q", ref)
	}
	return commit, nil
}

// worktreeHash hashes a local checkout: its commit and uncommitted changes.
func worktreeHash(dir, path string) (string, error) {
	head, err := exec.Command("git", "-C", dir, "rev-parse", "HEAD").Output()
	if err != nil {
		return "", fmt.Errorf("%s is not a git checkout", dir)
	}
	diff, err := exec.Command("git", "-C", dir, "diff", "HEAD").Output()
	if err != nil {
		return "", err
	}
	untracked, err := exec.Command("git", "-C", dir, "status", "--porcelain", "--untracked-files=all").Output()
	if err != nil {
		return "", err
	}
	h := sha256.New()
	h.Write(head)
	h.Write(diff)
	h.Write(untracked)
	h.Write([]byte(path))
	return hex.EncodeToString(h.Sum(nil))[:16], nil
}
