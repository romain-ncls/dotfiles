package plan

import (
	"strings"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

func TestPlanKDE(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml": "modules:\n  - kde\nuser:\n  name: romain\n",
		"modules/kde/module.yaml": `
kde:
  kwinrc:
    Windows:
      Placement: Centered
      RollOverDesktops: false
  powerdevilrc:
    AC/Display:
      DimDisplayWhenIdle: false
  kdeglobals:
    KDE:
      LookAndFeelPackage: Amethyst
    Icons:
      Theme: amethyst # the global theme's default: only in kdedefaults
breeze-exceptions:
  - ExceptionPattern: mpv
    HideTitleBar: true
shortcuts:
  - name: Mute
    keys: Meta+É
    run: mutectl mute
  - component: kwin
    action: Window Maximize
    keys:
      - Meta+Up
  - component: kwin
    action: Overview
    keys: Meta+W
`,
	})
	write(t, root, map[string]string{
		"home/romain/.config/kwinrc": "[Windows]\nPlacement=Smart\nRollOverDesktops=false\n\n[Old]\nGone=1\n",
		"home/romain/.config/kglobalshortcutsrc": "[kwin]\nWindow Maximize=Meta+PgUp,Meta+PgUp,Maximize Window\n" +
			"Overview=Meta+W,Meta+W,Toggle Overview\n",
		"home/romain/.config/breezerc": "[Common]\nShadowSize=2\n\n[Windeco Exception 0]\nExceptionPattern=konsole\n",
		"home/romain/.config/kdedefaults/kdeglobals": "[Icons]\nTheme=amethyst\n",
	})
	home := state.New()
	home.KDE["kwinrc/Old/Gone"] = state.KDEKey{File: "kwinrc", Group: []string{"Old"}, Key: "Gone", Value: "1"}
	p := compute(t, c, root, m, nil, home)

	var lines []string
	for _, a := range p.Actions {
		if a.KDEFile == "" && a.Command == "" && !strings.Contains(a.Display, "applications") {
			continue
		}
		line := string(a.Op) + " " + a.KDEID + a.Display + a.Command
		if a.Op == OpKDE && !a.Delete {
			line += " = " + a.Value
		}
		lines = append(lines, line)
	}
	got := strings.Join(lines, "\n")
	for _, want := range []string{
		"write ~/.local/share/applications/net.local.lodestar-mute.desktop",
		"kde kwinrc/Windows/Placement = Centered",
		"adopt kwinrc/Windows/RollOverDesktops",
		"adopt kdeglobals/Icons/Theme",
		"adopt kglobalshortcutsrc/kwin/Overview",
		"kde powerdevilrc/AC/Display/DimDisplayWhenIdle = false",
		"kde kglobalshortcutsrc/services/net.local.lodestar-mute.desktop/_launch = Meta+É",
		"kde kglobalshortcutsrc/kwin/Window Maximize = Meta+Up,Meta+PgUp,Maximize Window",
		"kde kwinrc/Old/Gone",
		"kde-list breezerc: 1 entries",
		"plasma-apply-lookandfeel --apply 'Amethyst'",
		"org.kde.KWin reconfigure",
		"plasma-kglobalaccel",
	} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q in:\n%s", want, got)
		}
	}
	if strings.Contains(got, "kde kglobalshortcutsrc/kwin/Overview") {
		t.Errorf("an unchanged shortcut was planned:\n%s", got)
	}
	// the global theme comes before the keys, so the keys win
	if strings.Index(got, "plasma-apply-lookandfeel") > strings.Index(got, "kde kwinrc/Windows/Placement") {
		t.Errorf("the global theme must be applied before the keys:\n%s", got)
	}
}
