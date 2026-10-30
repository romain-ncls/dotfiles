// Package runlog keeps a log of each command that changes the machine
// (apply, upgrade, prune) in ~/.local/state/lodestar/logs: what lodestar
// printed, the commands' errors, and how it ended, without colours. last.log
// points to the newest.
package runlog

import (
	"bytes"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
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
	esc   int    // where Write is in an escape sequence: 0 outside, 1 after ESC, 2 in CSI
	line  []byte // the line being written, held until its end
	cr    bool   // the last byte was a carriage return
	start time.Time
}

// question ends a line that waits for an answer typed on the terminal
// (pacman's, yay's): the answer reaches the command, not the log.
var question = regexp.MustCompile(`\[[Yy]/[Nn]\]\s*$`)

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

// Write adds p without its escape sequences (colours, cursor moves). A line
// redrawn after carriage returns (a progress bar) keeps only its last state,
// and a question gets a line of its own.
func (l *Log) Write(p []byte) (int, error) {
	if l == nil {
		return len(p), nil
	}
	l.mu.Lock()
	defer l.mu.Unlock()
	var out []byte
	for _, b := range p {
		switch {
		case l.esc == 1 && b == '[':
			l.esc = 2
			continue
		case l.esc == 1:
			l.esc = 0 // a two-byte sequence
			continue
		case l.esc == 2:
			if b >= 0x40 && b <= 0x7e {
				l.esc = 0
			}
			continue
		case b == 0x1b:
			l.esc = 1
			continue
		}
		if l.cr && b != '\n' {
			l.line = l.line[:0] // redrawn
		}
		l.cr = b == '\r'
		switch b {
		case '\r':
		case '\n':
			out = append(append(out, l.line...), '\n')
			l.line = l.line[:0]
		default:
			l.line = append(l.line, b)
		}
	}
	if question.Match(l.line) {
		out = append(append(out, bytes.TrimRight(l.line, " ")...), " (answered on the terminal)\n"...)
		l.line = l.line[:0]
	}
	if _, err := l.f.Write(out); err != nil {
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
	if len(l.line) > 0 {
		l.f.Write(append(l.line, '\n'))
	}
	return l.f.Close()
}

// PacmanLog is where pacman logs its transactions.
const PacmanLog = "/var/log/pacman.log"

// change is a package pacman's log says a transaction changed.
var change = regexp.MustCompile(`^\[([^\]]+)\] \[ALPM\] ((?:installed|upgraded|downgraded|reinstalled|removed) .*)$`)

// Transactions adds what pacman changed since a time, as its log tells: what
// the questions answered on the terminal led to.
func (l *Log) Transactions(pacmanLog string, since time.Time) {
	if l == nil {
		return
	}
	data, err := os.ReadFile(pacmanLog)
	if err != nil {
		return
	}
	var changes []string
	for _, line := range strings.Split(string(data), "\n") {
		m := change.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		if t, err := time.Parse("2006-01-02T15:04:05-0700", m[1]); err == nil && !t.Before(since.Truncate(time.Second)) {
			changes = append(changes, m[2])
		}
	}
	if len(changes) == 0 {
		l.Printf("(pacman: no package installed, upgraded or removed)\n")
		return
	}
	l.Printf("(pacman changed:)\n")
	for _, c := range changes {
		l.Printf("  %s\n", c)
	}
}
