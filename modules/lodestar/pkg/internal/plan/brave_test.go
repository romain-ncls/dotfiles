package plan

import (
	"path/filepath"
	"strings"
	"testing"
)

// brave-flags.conf gets the modules' flags, then one --load-extension with
// every extension folder: ~/ expanded, a module's folder absolute.
func TestPlanBraveFlags(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml": "modules:\n  - session\n  - mute\nuser:\n  name: romain\n",
		"modules/session/module.yaml": "brave:\n  flags:\n    - --password-store=kwallet6\n" +
			"  extensions:\n    - ~/.local/share/new-tab\n",
		"modules/mute/module.yaml":       "brave:\n  extensions:\n    - ext\n",
		"modules/mute/ext/manifest.json": "{}",
	})
	var content string
	for _, a := range compute(t, c, root, m, nil, nil).Actions {
		if a.Display == "~/.config/brave-flags.conf" {
			content = string(a.Content)
		}
	}
	ext := filepath.Join(c.Repo, "modules/mute/ext")
	want := "--password-store=kwallet6\n--load-extension=/home/romain/.local/share/new-tab," + ext + "\n"
	if !strings.HasPrefix(content, "#") || !strings.HasSuffix(content, want) {
		t.Fatalf("brave-flags.conf =\n%s\nwant it to end with\n%s", content, want)
	}
	for _, line := range strings.Split(strings.TrimSpace(content), "\n") {
		if !strings.HasPrefix(line, "#") && !strings.HasPrefix(line, "--") {
			t.Errorf("line %q: the launcher takes each line as one argument", line)
		}
	}
}

// Without brave: anywhere, lodestar doesn't write the file.
func TestPlanNoBrave(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml":      "modules:\n  - a\nuser:\n  name: romain\n",
		"modules/a/home/.config/x": "x\n",
	})
	for _, a := range compute(t, c, root, m, nil, nil).Actions {
		if a.Display == "~/.config/brave-flags.conf" {
			t.Fatalf("wrote brave-flags.conf without brave: %+v", a)
		}
	}
}
