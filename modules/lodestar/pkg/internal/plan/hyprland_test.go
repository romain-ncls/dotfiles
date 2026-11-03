package plan

import (
	"strings"
	"testing"
)

// Part of the French layout's keymap, as xkbcli writes it.
const frKeymap = `xkb_symbols "pc+fr+inet(evdev)" {
	key <TLDE>               {	[     twosuperior,      asciitilde,         notsign,         notsign ] };
	key <AE01>               {	[       ampersand,               1,     onesuperior,      exclamdown ] };
	key <AE02>               {	[          eacute,               2,      asciitilde,       oneeighth ] };
	key <AE03>               {	[        quotedbl,               3,      numbersign,        sterling ] };
	key <AD01>               {	[               a,               A,              ae,              AE ] };
	key <AC01>               {	[               q,               Q,              at,     Greek_OMEGA ] };
	key <AC11>               {	[          ugrave,         percent, dead_circumflex,      dead_caron ] };
	key <AB07>               {	[           comma,        question,      dead_acute, dead_doubleacute ] };
	key <AB08>               {	[       semicolon,          period,           U2022,        multiply ] };
	key <AB09>               {	[           colon,           slash,  periodcentered,        division ] };
	key <LSGT>               {	[            less,         greater,             bar,       brokenbar ] };
	key <RTRN>               {	[          Return ] };
};
`

func TestHyprKeys(t *testing.T) {
	levels := parseKeymap(frKeymap)
	for kde, want := range map[string]string{
		"Meta+Shift+Return": "SUPER + SHIFT + Return",
		"Meta+É":            "SUPER + eacute",
		"Meta+&":            "SUPER + ampersand",
		`Meta+"`:            "SUPER + quotedbl",
		"Meta+:":            "SUPER + colon",
		"Meta+/":            "SUPER + SHIFT + colon", // Shift+: on AZERTY
		"Meta+Ctrl+/":       "SUPER + CTRL + SHIFT + colon",
		"Meta+.":            "SUPER + SHIFT + semicolon",
		"Meta+,":            "SUPER + comma",
		"Meta+<":            "SUPER + less",
		"Meta+~":            "SUPER + SHIFT + twosuperior",
		"Meta+1":            "SUPER + SHIFT + ampersand",
		"Meta+A":            "SUPER + a",
		"Meta+End":          "SUPER + End",
		"Meta+Num+*":        "SUPER + KP_Multiply",
		"Launch (6)":        "XF86Launch6",
		"ScrollLock":        "Scroll_Lock",
		"Sleep":             "XF86Sleep",
		"Ctrl+Alt+F2":       "CTRL + ALT + F2",
	} {
		got, err := hyprKeys(kde, levels)
		if err != nil {
			t.Errorf("%s: %v", kde, err)
		} else if got != want {
			t.Errorf("%s: got %q, want %q", kde, got, want)
		}
	}
	for _, kde := range []string{"Meta+@", "Hyper+A", "Meta+Zork"} {
		if got, err := hyprKeys(kde, levels); err == nil {
			t.Errorf("%s: got %q, want an error", kde, got)
		}
	}
}

func TestLuaString(t *testing.T) {
	for s, want := range map[string]string{
		`brave "https://claude.ai/new"`: `[[brave "https://claude.ai/new"]]`,
		"a]]b":                          "[=[a]]b]=]",
		"ends]":                         "[=[ends]]=]",
	} {
		if got := luaString(s); got != want {
			t.Errorf("%q: got %s, want %s", s, got, want)
		}
	}
}

func TestPlanHyprlandShortcuts(t *testing.T) {
	keymap := xkbKeymap
	t.Cleanup(func() { xkbKeymap = keymap })
	var asked string
	xkbKeymap = func(layout string) (string, error) {
		asked = layout
		return frKeymap, nil
	}

	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml": "modules:\n  - kde\n  - hyprland\nuser:\n  name: romain\n",
		"modules/kde/module.yaml": `
kde:
  kxkbrc:
    Layout:
      LayoutList: fr
shortcuts:
  - name: Mute
    keys: Meta+É
    run: mutectl mute
  - name: Soundboard replay
    keys:
      - Meta+/
      - Meta+Ctrl+/
    run: soundboard replay
  - component: kwin
    action: Window Maximize
    keys: Meta+Up
`,
		"modules/hyprland/module.yaml": "packages:\n  - hyprland\n",
	})
	m.Repos["hyprland"] = true
	p := compute(t, c, root, m, nil, nil)

	if asked != "fr" {
		t.Errorf("asked xkbcli for layout %q, want fr", asked)
	}
	var content string
	for _, a := range p.Actions {
		if a.Display == HyprlandShortcuts {
			content = string(a.Content)
		}
	}
	for _, want := range []string{
		`hl.bind([[SUPER + eacute]], hl.dsp.exec_cmd([[mutectl mute]]), { description = [[Mute]] })`,
		`hl.bind([[SUPER + SHIFT + colon]], hl.dsp.exec_cmd([[soundboard replay]]), { description = [[Soundboard replay]] })`,
		`hl.bind([[SUPER + CTRL + SHIFT + colon]], hl.dsp.exec_cmd([[soundboard replay]]), { description = [[Soundboard replay]] })`,
	} {
		if !strings.Contains(content, want) {
			t.Errorf("missing %s in:\n%s", want, content)
		}
	}
	if strings.Contains(content, "Maximize") {
		t.Errorf("a KDE action became a bind:\n%s", content)
	}
}

func TestPlanNoHyprland(t *testing.T) {
	c, root, m := setup(t, map[string]string{
		"hosts/box/host.yaml":     "modules:\n  - kde\nuser:\n  name: romain\n",
		"modules/kde/module.yaml": "shortcuts:\n  - name: Mute\n    keys: Meta+É\n    run: mutectl mute\n",
	})
	p := compute(t, c, root, m, nil, nil)
	for _, a := range p.Actions {
		if a.Display == HyprlandShortcuts {
			t.Errorf("Hyprland binds planned on a host without Hyprland")
		}
	}
}
