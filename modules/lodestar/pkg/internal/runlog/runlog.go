// Package runlog keeps a log of each command that changes the machine
// (apply, upgrade, prune) in ~/.local/state/lodestar/logs: what lodestar
// printed, the commands' errors, and how it ended, without colours. last.log
// points to the newest.
package runlog

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"
)

// Dir is the logs' folder in the user's home.
const Dir = ".local/state/lodestar/logs"

// keep is how many logs stay.
const keep = 30

// Log is one run's log. A nil *Log logs nothing.
type Log struct {
	mu    sync.Mutex
	f     *os.File
	esc   int // where Write is in an escape sequence: 0 outside, 1 after ESC, 2 in CSI
	start time.Time
}

// Open starts the log of a command (args: the command line after lodestar).
func Open(home string, args []string) (*Log, error) {
	dir := filepath.Join(home, Dir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	now := time.Now()
	name := now.Format("2006-01-02T15-04-05") + "-" + args[0] + ".log"
	f, err := os.OpenFile(filepath.Join(dir, name), os.O_WRONLY|os.O_APPEND|os.O_CREATE|os.O_EXCL, 0o644) // append: the root process writes to it too
	if err != nil {
		return nil, err
	}
	last := filepath.Join(dir, "last.log")
	os.Remove(last)
	os.Symlink(name, last)
	prune(dir)
	host, _ := os.Hostname()
	l := &Log{f: f, start: now}
	l.Printf("lodestar %s\n%s · %s\n\n", strings.Join(args, " "), host, now.Format("2006-01-02 15:04:05"))
	return l, nil
}

// Append opens an existing log, for the root process.
func Append(path string) (*Log, error) {
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	return &Log{f: f}, nil
}

// prune removes the oldest logs beyond keep.
func prune(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	var logs []string
	for _, e := range entries {
		if e.Type().IsRegular() && strings.HasSuffix(e.Name(), ".log") {
			logs = append(logs, e.Name())
		}
	}
	slices.Sort(logs) // the names start with the date
	for len(logs) > keep {
		os.Remove(filepath.Join(dir, logs[0]))
		logs = logs[1:]
	}
}

// Path is the log file's path.
func (l *Log) Path() string {
	if l == nil {
		return ""
	}
	return l.f.Name()
}

// Write adds p without its escape sequences (colours, cursor moves).
func (l *Log) Write(p []byte) (int, error) {
	if l == nil {
		return len(p), nil
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	clean := make([]byte, 0, len(p))
	for _, b := range p {
		switch {
		case l.esc == 1 && b == '[':
			l.esc = 2
		case l.esc == 1:
			l.esc = 0 // a two-byte sequence
		case l.esc == 2:
			if b >= 0x40 && b <= 0x7e {
				l.esc = 0
			}
		case b == 0x1b:
			l.esc = 1
		default:
			clean = append(clean, b)
		}
	}
	if _, err := l.f.Write(clean); err != nil {
		return 0, err
	}
	return len(p), nil
}

// Printf adds a line to the log only.
func (l *Log) Printf(format string, args ...any) {
	if l != nil {
		fmt.Fprintf(l, format, args...)
	}
}

// Tee returns a writer to w and the log.
func (l *Log) Tee(w io.Writer) io.Writer {
	if l == nil {
		return w
	}
	return io.MultiWriter(w, l)
}

// End writes how the command ended, and closes the log.
func (l *Log) End(err error) error {
	if l == nil {
		return nil
	}
	took := time.Since(l.start).Round(time.Second)
	if err != nil {
		l.Printf("\n== failed after %s: %v\n", took, err)
	} else {
		l.Printf("\n== done in %s\n", took)
	}
	return l.Close()
}

// Close closes the log (the root process's copy).
func (l *Log) Close() error {
	if l == nil {
		return nil
	}
	return l.f.Close()
}
