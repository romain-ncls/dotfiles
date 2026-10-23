package kdesnap

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/glob"
)

func TestTakeAndDiff(t *testing.T) {
	dir := t.TempDir()
	write := func(name, text string) { os.WriteFile(filepath.Join(dir, name), []byte(text), 0o600) }
	write("kwinrc", "[Windows]\nPlacement=Smart\nGone=1\n\n[Tiling][abc]\nlayout=x\n")
	write("kdeglobals", "[KDE]\nSingleClick=false\n")
	before, err := Take(dir)
	if err != nil {
		t.Fatal(err)
	}
	write("kwinrc", "[Windows]\nPlacement=Centered\n\n[Tiling][abc]\nlayout=y\n")
	write("dolphinrc", "[MainWindow]\nState=AAA\n\n[General]\nShowFullPath=true\n")
	after, _ := Take(dir)

	var got []string
	state := glob.New(State)
	for _, ch := range Diff(before, after) {
		if !state.Match(ch.ID()) {
			got = append(got, ch.ID())
		}
	}
	want := []string{"dolphinrc/General/ShowFullPath", "kwinrc/Windows/Gone", "kwinrc/Windows/Placement"}
	if len(got) != len(want) {
		t.Fatalf("changes = %q, want %q", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("changes = %q, want %q", got, want)
		}
	}

	p := filepath.Join(dir, "snap.json")
	if err := after.Save(p); err != nil {
		t.Fatal(err)
	}
	loaded, err := Load(p)
	if err != nil || loaded["kwinrc"]["Windows/Placement"] != "Centered" {
		t.Errorf("load = %v, %v", loaded, err)
	}
}
