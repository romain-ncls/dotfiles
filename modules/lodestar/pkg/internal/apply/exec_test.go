package apply

import (
	"strings"
	"testing"
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
