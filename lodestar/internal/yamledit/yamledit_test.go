package yamledit

import (
	"os"
	"path/filepath"
	"testing"
)

const module = `# KDE settings
packages:
  - plasma-meta # the desktop

kde:
  kwinrc:
    Windows:
      Placement: Smart # was the default
  kdeglobals:
    KDE:
      LookAndFeelPackage: org.kde.breezedark.desktop

shortcuts:
  - name: Mute
    keys: Meta+É
    run: mutectl mute
`

func TestEdits(t *testing.T) {
	p := filepath.Join(t.TempDir(), "module.yaml")
	os.WriteFile(p, []byte(module), 0o644)
	steps := []func() error{
		func() error { return SetKDEKey(p, "kwinrc", []string{"Windows"}, "Placement", "Centered") },
		func() error { return SetKDEKey(p, "kwinrc", []string{"Windows"}, "RollOverDesktops", "false") },
		func() error { return SetKDEKey(p, "kwinrc", []string{"Effect-blur"}, "BlurStrength", "11") },
		func() error {
			return SetKDEKey(p, "powerdevilrc", []string{"AC", "Display"}, "DimDisplayWhenIdle", "false")
		},
		func() error {
			return SetKDEKey(p, "kglobalshortcutsrc", []string{"kwin"}, "Window Maximize", "Meta+Up,Meta+PgUp,Maximize Window")
		},
		func() error { return AddToList(p, "kde-ignore", "dolphinrc/MainWindow/*") },
		func() error { return AddToList(p, "kde-ignore", "*/Seen") },
		func() error { return AddToList(p, "kde-ignore", "dolphinrc/MainWindow/*") },
	}
	for i, step := range steps {
		if err := step(); err != nil {
			t.Fatalf("step %d: %v", i, err)
		}
	}
	got, _ := os.ReadFile(p)
	want := `# KDE settings
packages:
  - plasma-meta # the desktop

kde:
  kwinrc:
    Windows:
      Placement: Centered # was the default
      RollOverDesktops: false
    Effect-blur:
      BlurStrength: 11
  kdeglobals:
    KDE:
      LookAndFeelPackage: org.kde.breezedark.desktop
  powerdevilrc:
    AC/Display:
      DimDisplayWhenIdle: false
  kglobalshortcutsrc:
    kwin:
      Window Maximize: Meta+Up,Meta+PgUp,Maximize Window

shortcuts:
  - name: Mute
    keys: Meta+É
    run: mutectl mute

kde-ignore:
  - dolphinrc/MainWindow/*
  - "*/Seen"
`
	if string(got) != want {
		t.Errorf("got:\n%s\nwant:\n%s", got, want)
	}
}

func TestNewFile(t *testing.T) {
	p := filepath.Join(t.TempDir(), "module.yaml")
	if err := SetKDEKey(p, "kwinrc", []string{"Windows"}, "Placement", "Centered"); err != nil {
		t.Fatal(err)
	}
	got, _ := os.ReadFile(p)
	if string(got) != "kde:\n  kwinrc:\n    Windows:\n      Placement: Centered\n" {
		t.Errorf("got:\n%s", got)
	}
}
