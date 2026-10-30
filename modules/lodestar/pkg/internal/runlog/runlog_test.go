package runlog

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
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

func TestProgressAndQuestions(t *testing.T) {
	home := t.TempDir()
	l, err := Open(home, []string{"upgrade"})
	if err != nil {
		t.Fatal(err)
	}
	// curl's progress bar, then pacman's question in pieces, then makepkg.
	fmt.Fprint(l, "  % Total\n  0  0\r")
	fmt.Fprint(l, " 50 284M\r100 284M\r")
	fmt.Fprint(l, "\n    claude ... Passed\n:: ")
	fmt.Fprint(l, "Proceed with installation? [Y/n] ")
	fmt.Fprint(l, "    cc-legal ... Skipped\r\n")
	fmt.Fprint(l, "unfinished")
	l.Close()

	data, _ := os.ReadFile(l.Path())
	want := "  % Total\n100 284M\n    claude ... Passed\n:: Proceed with installation? [Y/n] (answered on the terminal)\n    cc-legal ... Skipped\nunfinished\n"
	if got := string(data); !strings.HasSuffix(got, want) {
		t.Errorf("got:\n%q\nwant suffix:\n%q", got, want)
	}
}

func TestTransactions(t *testing.T) {
	pacman := filepath.Join(t.TempDir(), "pacman.log")
	os.WriteFile(pacman, []byte(`[2026-10-30T09:05:00+0100] [ALPM] upgraded old (1-1 -> 2-1)
[2026-10-30T09:05:05+0100] [PACMAN] starting full system upgrade
[2026-10-30T09:05:30+0100] [ALPM] upgraded fribidi (1.0.17-1 -> 1.0.18-1)
[2026-10-30T09:05:30+0100] [ALPM-SCRIPTLET] installed nothing
[2026-10-30T09:05:56+0100] [ALPM] removed foo (1-1)
`), 0o644)
	home := t.TempDir()
	l, _ := Open(home, []string{"upgrade"})
	since, _ := time.Parse(time.RFC3339Nano, "2026-10-30T09:05:04.6+01:00")
	l.Transactions(pacman, since)
	l.Transactions(pacman, since.Add(time.Hour))
	l.Close()

	data, _ := os.ReadFile(l.Path())
	want := "(pacman changed:)\n  upgraded fribidi (1.0.17-1 -> 1.0.18-1)\n  removed foo (1-1)\n(pacman: no package installed, upgraded or removed)\n"
	if got := string(data); !strings.HasSuffix(got, want) {
		t.Errorf("got:\n%s\nwant suffix:\n%s", got, want)
	}
}
