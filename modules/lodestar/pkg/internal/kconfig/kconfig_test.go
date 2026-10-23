package kconfig

import (
	"strings"
	"testing"
)

const sample = `[$Version]
update_info=kwinrules.upd:a,kwinrules.upd:b

[1]
Description=Settings for Spotify
desktops=\\0
wmclass=Spotify

[General]
Order=1

[Libinput][1133][16478][Logitech M720 Triathlon]
PointerAccelerationProfile=1

[Desktop Entry][$i]
Name[fr]=Bonjour
Path[$e]=$HOME/x
Lead=\sspace
Tab=a\tb
`

func TestParse(t *testing.T) {
	f := Parse([]byte(sample))
	for _, tc := range []struct {
		path      []string
		key, want string
	}{
		{[]string{"$Version"}, "update_info", "kwinrules.upd:a,kwinrules.upd:b"},
		{[]string{"1"}, "desktops", `\0`},
		{[]string{"Libinput", "1133", "16478", "Logitech M720 Triathlon"}, "PointerAccelerationProfile", "1"},
		{[]string{"Desktop Entry"}, "Name[fr]", "Bonjour"},
		{[]string{"Desktop Entry"}, "Path", "$HOME/x"},
		{[]string{"Desktop Entry"}, "Lead", " space"},
		{[]string{"Desktop Entry"}, "Tab", "a\tb"},
	} {
		if got, ok := f.Get(tc.path, tc.key); !ok || got != tc.want {
			t.Errorf("%v %s = %q (%v), want %q", tc.path, tc.key, got, ok, tc.want)
		}
	}
	if got := string(f.Bytes()); got != sample {
		t.Errorf("round trip changed the file:\n%s", got)
	}
}

func TestReplaceGroups(t *testing.T) {
	f := Parse([]byte(sample))
	f.DeleteGroups(func(p []string) bool { return len(p) == 1 && p[0] == "1" })
	f.SetGroup([]string{"General"}, map[string]string{"Order": "1,2"})
	f.SetGroup([]string{"2"}, map[string]string{"wmclass": "discord", "Description": " lead"})
	out := string(f.Bytes())
	for _, want := range []string{"[$Version]\nupdate_info=", "[General]\nOrder=1,2\n", "[2]\nDescription=\\slead\nwmclass=discord\n", "[Desktop Entry][$i]\n"} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, "Spotify") {
		t.Errorf("group [1] not deleted:\n%s", out)
	}
	if Escape("a\\b\nc") != `a\\b\nc` {
		t.Errorf("escape = %q", Escape("a\\b\nc"))
	}
}
