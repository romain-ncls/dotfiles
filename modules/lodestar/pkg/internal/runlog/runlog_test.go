package runlog

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestLog(t *testing.T) {
	home := t.TempDir()
	l, err := Open(home, []string{"apply", "--yes"})
	if err != nil {
		t.Fatal(err)
	}
	// A colour split across writes, as a pipe may deliver it.
	fmt.Fprint(l, "\033[1mKDE\033[0m\n  \033[3")
	fmt.Fprint(l, "2m+\033[0m kwinrc\n")
	root, err := Append(l.Path())
	if err != nil {
		t.Fatal(err)
	}
	fmt.Fprint(root, "==> install foo\n")
	root.Close()
	l.End(errors.New("boom"))

	data, err := os.ReadFile(filepath.Join(home, Dir, "last.log"))
	if err != nil {
		t.Fatal(err)
	}
	got := string(data)
	for _, want := range []string{"lodestar apply --yes\n", "KDE\n  + kwinrc\n==> install foo\n", "== failed after 0s: boom\n"} {
		if !strings.Contains(got, want) {
			t.Errorf("log lacks %q:\n%s", want, got)
		}
	}
	if strings.Contains(got, "\033") {
		t.Errorf("escape sequences left:\n%q", got)
	}
}

func TestPrune(t *testing.T) {
	dir := t.TempDir()
	for i := range keep + 5 {
		os.WriteFile(filepath.Join(dir, fmt.Sprintf("2026-01-%02dT00-00-00-apply.log", i+1)), nil, 0o644)
	}
	prune(dir)
	entries, _ := os.ReadDir(dir)
	if len(entries) != keep || entries[0].Name() != "2026-01-06T00-00-00-apply.log" {
		t.Errorf("kept %d, the oldest %s", len(entries), entries[0].Name())
	}
}
