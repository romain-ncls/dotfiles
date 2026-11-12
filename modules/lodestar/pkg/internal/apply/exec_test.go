package apply

import (
	"io"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

func TestNotFound(t *testing.T) {
	for _, c := range []struct {
		name   string
		writes []string
		want   bool
	}{
		{"pacman, in two writes", []string{
			"error: failed retrieving file 'ollama-0.40.7-1-x86_64.pkg.tar.zst' from geo.mirror.pkgbuild.com : The requested URL ",
			"returned error: 404\nwarning: failed to retrieve some files\n",
		}, true},
		{"pacman, translated", []string{
			"erreur : échec de récupération du fichier « ollama-0.40.7-1-x86_64.pkg.tar.zst » depuis geo.mirror.pkgbuild.com : The requested URL returned error: 404\n",
		}, true},
		{"makepkg, an AUR source", []string{
			"  -> Downloading foo-1.0.tar.gz...\ncurl: (22) The requested URL returned error: 404\n",
		}, false},
		{"another failure", []string{
			"error: failed to prepare transaction (could not satisfy dependencies)\n",
		}, false},
	} {
		var out strings.Builder
		n := &notFound{w: &out}
		for _, w := range c.writes {
			n.Write([]byte(w))
		}
		if n.seen != c.want {
			t.Errorf("%s: seen = %v, want %v", c.name, n.seen, c.want)
		}
		if out.String() != strings.Join(c.writes, "") {
			t.Errorf("%s: passed on %q", c.name, out.String())
		}
	}
}

// A file in a folder only root can read (NetworkManager's connections) is
// planned as maybe replacing an original. When it doesn't exist, the write
// goes on, and the state records no original to put back.
func TestWriteOriginalMissing(t *testing.T) {
	root := t.TempDir()
	e := &env{root: root, st: state.New(), out: io.Discard}
	for _, c := range []struct {
		name, existing string
		wantOriginal   bool
	}{
		{"new file", "", false},
		{"file no package owns", "mine\n", true},
	} {
		path := "/etc/NetworkManager/system-connections/" + strings.ReplaceAll(c.name, " ", "-")
		if c.existing != "" {
			os.MkdirAll(filepath.Dir(root+path), 0o755)
			if err := os.WriteFile(root+path, []byte(c.existing), 0o600); err != nil {
				t.Fatal(err)
			}
		}
		a := &plan.Action{Op: plan.OpWrite, Phase: plan.PhaseSystem, Path: path, Display: path,
			Content: []byte("new\n"), Mode: 0o600, Original: true}
		if err := e.do(a); err != nil {
			t.Fatalf("%s: %v", c.name, err)
		}
		if got, _ := os.ReadFile(root + path); string(got) != "new\n" {
			t.Errorf("%s: file holds %q", c.name, got)
		}
		if got := e.st.Files[path].Original; got != c.wantOriginal {
			t.Errorf("%s: state records an original: %v, want %v", c.name, got, c.wantOriginal)
		}
		kept, err := os.ReadFile(root + filepath.Join(state.OriginalsDir, path))
		if c.wantOriginal && string(kept) != c.existing {
			t.Errorf("%s: original kept as %q (%v)", c.name, kept, err)
		}
		if !c.wantOriginal && err == nil {
			t.Errorf("%s: an original was kept", c.name)
		}
	}
}
