package config

import (
	"testing"

	"github.com/goccy/go-yaml"
)

func TestValueKeepsText(t *testing.T) {
	var m struct {
		KDE      map[string]map[string]map[string]Value `yaml:"kde"`
		Keys     StringList                             `yaml:"keys"`
		One      StringList                             `yaml:"one"`
		Firewall Firewall                               `yaml:"firewall"`
	}
	src := `
kde:
  kwinrc:
    Windows:
      Placement: Centered
      Flag: no
      Mode: 0440
      Quoted: "a: b"
      Float: 1.10
      Empty:
keys:
  - Meta+É
  - Ctrl+Alt+T
one: Meta+&
firewall:
  tcp:
    - 1714-1764
    - 22
`
	if err := yaml.UnmarshalWithOptions([]byte(src), &m, yaml.DisallowUnknownField()); err != nil {
		t.Fatal(err)
	}
	w := m.KDE["kwinrc"]["Windows"]
	for k, want := range map[string]string{"Placement": "Centered", "Flag": "no", "Mode": "0440", "Quoted": "a: b", "Float": "1.10", "Empty": ""} {
		if string(w[k]) != want {
			t.Errorf("%s = %q, want %q", k, w[k], want)
		}
	}
	if len(m.Keys) != 2 || m.Keys[0] != "Meta+É" || len(m.One) != 1 || m.One[0] != "Meta+&" {
		t.Errorf("keys = %q, one = %q", m.Keys, m.One)
	}
	if len(m.Firewall.TCP) != 2 || m.Firewall.TCP[0] != "1714-1764" || m.Firewall.TCP[1] != "22" {
		t.Errorf("tcp = %q", m.Firewall.TCP)
	}
}
