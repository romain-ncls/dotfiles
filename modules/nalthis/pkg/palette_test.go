package main

import "testing"

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
