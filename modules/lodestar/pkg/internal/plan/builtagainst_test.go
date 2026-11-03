package plan

import (
	"slices"
	"strings"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

// A local package built against hyprland (a plugin) is rebuilt by a new
// Hyprland, and only then.
func TestPlanBuiltAgainst(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml":         "modules:\n  - plugin\nuser:\n  name: romain\n",
		"modules/plugin/module.yaml":  "pkg:\n  built-against:\n    - hyprland\n",
		"modules/plugin/pkg/PKGBUILD": "pkgname=myplugin\npkgver=1\n",
	})
	m.Installed["myplugin"] = machine.Package{Name: "myplugin"}
	m.Installed["hyprland"] = machine.Package{Name: "hyprland", Version: "0.57.0-1"}

	builds := func(p *Plan) []*Action {
		var out []*Action
		for _, a := range p.Actions {
			if a.Op == OpBuild {
				out = append(out, a)
			}
		}
		return out
	}

	first := builds(compute(t, c, root, m, nil, nil))
	if len(first) != 1 || !strings.HasSuffix(first[0].Hash, "\nhyprland=0.57.0-1") {
		t.Fatalf("first plan's builds = %+v", first)
	}
	home := state.New()
	home.Packages = map[string]state.Built{"plugin": {Hash: first[0].Hash, Names: []string{"myplugin"}}}

	if again := builds(compute(t, c, root, m, nil, home)); len(again) != 0 {
		t.Errorf("rebuilt for the same Hyprland: %+v", again)
	}

	m.Installed["hyprland"] = machine.Package{Name: "hyprland", Version: "0.58.0-1"}
	p := compute(t, c, root, m, nil, home)
	if !slices.ContainsFunc(summary(p), func(s string) bool {
		return strings.HasSuffix(s, "myplugin built against another hyprland")
	}) {
		t.Errorf("a new Hyprland didn't rebuild it: %v", summary(p))
	}
}
