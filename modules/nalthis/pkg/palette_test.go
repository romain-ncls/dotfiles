package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The default knobs must give the surfaces picked on the design page.
func TestDefaultSurfaces(t *testing.T) {
	want := map[float64]string{0.199: "#12161b", 0.229: "#191d23", 0.266: "#21262d", 0.299: "#282e36", 0.341: "#323942"}
	for i, l := range surfaceL {
		got := OKLCH(l, baseChroma*chromaRamp[i], Defaults.Hue).Hex()
		if got != want[l] {
			t.Errorf("surface %d: got %s, want %s", i, got, want[l])
		}
	}
}

func TestMergeKeepsOtherGroups(t *testing.T) {
	base := []Group{{"General", [][2]string{{"ColorScheme", "BreezeDark"}}}, {"KDE", [][2]string{{"widgetStyle", "Breeze"}}}}
	out := merge(base, Scheme("Nalthis", Defaults))
	if out[0].Keys[0] != [2]string{"ColorScheme", "Nalthis"} {
		t.Errorf("General: %v", out[0].Keys)
	}
	if out[1].Name != "KDE" || out[1].Keys[0][1] != "Breeze" {
		t.Errorf("KDE group changed: %v", out[1])
	}
}

func TestOKLCHRoundTrip(t *testing.T) {
	for _, c := range oneDark {
		l, ch, h := toOKLCH(c)
		if got := OKLCH(l, ch, h); got != c {
			t.Errorf("%v → (%.3f %.3f %.1f) → %v", c, l, ch, h, got)
		}
	}
}

func TestINIRoundTrip(t *testing.T) {
	in := "Default=1\n# a comment\n[A]\nk=v\n# inside\n\n[B][C]\nx=a=b\n\n"
	path := filepath.Join(t.TempDir(), "rc")
	if err := os.WriteFile(path, []byte(in), 0o644); err != nil {
		t.Fatal(err)
	}
	groups, err := readINI(path)
	if err != nil {
		t.Fatal(err)
	}
	var out strings.Builder
	if err := writeINI(&out, groups); err != nil {
		t.Fatal(err)
	}
	want := "Default=1\n# a comment\n\n[A]\nk=v\n# inside\n\n[B][C]\nx=a=b\n\n"
	if out.String() != want {
		t.Errorf("got %q, want %q", out.String(), want)
	}
}

func TestMergeKeepsTitleBarFont(t *testing.T) {
	base := []Group{{"WM", [][2]string{{"activeBackground", "1,2,3"}, {"activeFont", "Inter,10"}}}}
	out := merge(base, Scheme("Nalthis", Defaults))
	keys := map[string]string{}
	for _, kv := range out[0].Keys {
		keys[kv[0]] = kv[1]
	}
	if keys["activeFont"] != "Inter,10" || keys["activeBackground"] == "1,2,3" {
		t.Errorf("WM: %v", out[0].Keys)
	}
}

func TestEnsureImportPutsKDEsFirst(t *testing.T) {
	dir := t.TempDir()
	for name, old := range map[string]string{"none": "", "ours": gtkImport + "\n", "kde": kdeImport, "both": kdeImport + "\n" + gtkImport + "\n"} {
		path := filepath.Join(dir, name)
		if old != "" {
			if err := os.WriteFile(path, []byte(old), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		if err := ensureImport(path); err != nil {
			t.Fatal(err)
		}
		got, _ := os.ReadFile(path)
		if want := kdeImport + "\n" + gtkImport + "\n"; string(got) != want {
			t.Errorf("%s: got %q, want %q", name, got, want)
		}
	}
}

func TestMergeLeavesBaseAlone(t *testing.T) {
	base := []Group{{"General", [][2]string{{"ColorScheme", "BreezeDark"}}}}
	merge(base, Scheme("Nalthis", Defaults))
	if base[0].Keys[0][1] != "BreezeDark" {
		t.Errorf("base changed: %v", base[0].Keys)
	}
}

// apply tells the apps only when kdeglobals changes (apply-lumar runs it at
// every lodestar apply).
func TestApplyNotifiesOnlyChanges(t *testing.T) {
	dir := t.TempDir()
	t.Setenv("XDG_CONFIG_HOME", filepath.Join(dir, "config"))
	t.Setenv("XDG_DATA_HOME", filepath.Join(dir, "data"))
	calls := 0
	notifyApps = func([]Group) error { calls++; return nil }
	t.Cleanup(func() { notifyApps = notify })

	other := Defaults
	other.Hue += 10
	for i, k := range []Knobs{Defaults, Defaults, other, other, Defaults} {
		if err := apply(k); err != nil {
			t.Fatal(err)
		}
		if want := []int{1, 1, 2, 2, 3}[i]; calls != want {
			t.Errorf("apply %d: %d notifications, want %d", i, calls, want)
		}
	}
}

// KDE sorts kdeglobals' keys when it rewrites it: the same colors, in
// another order, are no change.
func TestSameINIIgnoresOrder(t *testing.T) {
	a := []Group{{"A", [][2]string{{"x", "1"}, {"y", "2"}}}, {"B", [][2]string{{"z", "3"}}}}
	b := []Group{{"B", [][2]string{{"z", "3"}}}, {"A", [][2]string{{"y", "2"}, {"x", "1"}}}}
	if !sameINI(a, b) {
		t.Error("same keys in another order: not the same")
	}
	b[0].Keys[0][1] = "4"
	if sameINI(a, b) {
		t.Error("another value: the same")
	}
}
