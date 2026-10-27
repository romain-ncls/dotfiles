package apply

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/romain-ncls/dotfiles/lodestar/internal/kdesnap"
	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
	"github.com/romain-ncls/dotfiles/lodestar/internal/runlog"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
	"github.com/romain-ncls/dotfiles/lodestar/internal/ui"
)

// RootCommand is the hidden command the root process runs as.
const RootCommand = "__root"

// request is what the user process sends to the root process on stdin.
type request struct {
	Root    string         `json:"root"`
	Repo    string         `json:"repo"`
	User    string         `json:"user"`
	Home    string         `json:"home"`
	Actions []*plan.Action `json:"actions"`
	// Snapper: "pre" takes the pre snapshot before the actions; a non-zero
	// PreNumber takes the matching post snapshot after them.
	Snapper   bool `json:"snapper"`
	PreNumber int  `json:"pre_number"`
	// Log is the run's log, which the root process appends to.
	Log string `json:"log,omitempty"`
}

type result struct {
	PreNumber int `json:"pre_number"`
}

// Output is where an apply prints.
type Output struct {
	Term *os.File    // the terminal (or whatever stdout is)
	Log  *runlog.Log // nil: no log
}

// progress is where lodestar's own lines go: the terminal and the log.
func (o Output) progress() io.Writer { return o.Log.Tee(o.Term) }

// commandOut is the commands' stdout. On a terminal it is the terminal
// itself, unlogged, for pacman's progress bars; their stderr, with the
// errors, goes to the log too.
func (o Output) commandOut() io.Writer {
	if o.Log != nil && ui.IsTerminal(o.Term) {
		return o.Term
	}
	return o.progress()
}

// Apply carries out the plan.
func Apply(p *plan.Plan, o Output) error {
	byPhase := map[plan.Phase][]*plan.Action{}
	for _, a := range p.Actions {
		byPhase[a.Phase] = append(byPhase[a.Phase], a)
	}

	if p.HasRoot() && os.Geteuid() != 0 {
		stop, err := HoldSudo(o.Log)
		if err != nil {
			return err
		}
		defer stop()
	}

	snap := p.HasRoot() && p.Root == "" && snapperConfigured()
	pre := 0
	if len(byPhase[plan.PhasePackages]) > 0 || snap {
		res, err := runRoot(request{Root: p.Root, Repo: p.Repo, User: p.User, Home: p.Home, Actions: byPhase[plan.PhasePackages], Snapper: snap}, o)
		if err != nil {
			return err
		}
		pre = res.PreNumber
	}
	// AUR packages and local builds, as the user: they record into the home
	// state, saved at once in case a later phase fails.
	if aur := byPhase[plan.PhaseAUR]; len(aur) > 0 {
		if err := runUser(p, aur, o, false); err != nil {
			return err
		}
	}
	if len(byPhase[plan.PhaseSystem]) > 0 || pre > 0 {
		if _, err := runRoot(request{Root: p.Root, Repo: p.Repo, User: p.User, Home: p.Home, Actions: byPhase[plan.PhaseSystem], PreNumber: pre}, o); err != nil {
			return err
		}
	}
	if home := byPhase[plan.PhaseHome]; len(home) > 0 {
		return runUser(p, home, o, true)
	}
	return nil
}

// runUser carries out user actions, and saves the home state (and, after
// the home phase, the KDE snapshot).
func runUser(p *plan.Plan, actions []*plan.Action, o Output, snapshot bool) error {
	path := p.Root + filepath.Join(p.Home, state.HomePath)
	st, err := state.Load(path)
	if err != nil {
		return err
	}
	e := &env{root: p.Root, user: p.User, repo: p.Repo, home: p.Home, st: st, out: o.progress(), cmdOut: o.commandOut()}
	if os.Geteuid() == 0 { // install, or a container: home files go to the user
		u, err := user.Lookup(p.User)
		if err != nil {
			return err
		}
		uid, _ := strconv.Atoi(u.Uid)
		gid, _ := strconv.Atoi(u.Gid)
		e.owner = &account{uid, gid}
	}
	runErr := runAll(e, actions)
	if err := st.Save(path); err != nil {
		return errors.Join(runErr, err)
	}
	e.giveTreeToUser(p.Root+p.Home, path)
	if !snapshot {
		return runErr
	}
	// The KDE snapshot kde review compares with.
	snapPath := p.Root + filepath.Join(p.Home, kdesnap.Path)
	if snap, err := kdesnap.Take(p.Root + filepath.Join(p.Home, ".config")); err == nil {
		if err := snap.Save(snapPath); err == nil {
			e.giveTreeToUser(p.Root+p.Home, snapPath)
		}
	}
	return runErr
}

// giveTreeToUser hands a file written as root in the user's home to the
// user, with the folders between it and the home: the user's next apply
// writes there.
func (e *env) giveTreeToUser(home, path string) {
	if e.owner == nil {
		return
	}
	for d := filepath.Dir(path); strings.HasPrefix(d, home+"/"); d = filepath.Dir(d) {
		os.Chown(d, e.owner.uid, e.owner.gid)
	}
	os.Chown(path, e.owner.uid, e.owner.gid)
}

func runAll(e *env, actions []*plan.Action) error {
	for _, a := range actions {
		fmt.Fprintln(e.out, "==> "+label(a))
		if err := e.do(a); err != nil {
			return fmt.Errorf("%s: %w", label(a), err)
		}
	}
	return nil
}

func label(a *plan.Action) string {
	switch {
	case a.Op == plan.OpKDE:
		return "kde " + a.KDEFile + " [" + strings.Join(a.KDEGroup, "][") + "] " + a.KDEKey
	case a.Op == plan.OpHook:
		return "hook " + a.Command
	case a.User != "":
		return string(a.Op) + " " + a.User
	case a.Display != "":
		return string(a.Op) + " " + a.Display
	case a.Module != "":
		return string(a.Op) + " " + a.Module
	case len(a.Names) > 0:
		return string(a.Op) + " " + strings.Join(a.Names, " ")
	case a.Unit != "":
		return string(a.Op) + " " + a.Unit
	case a.Command != "":
		return "run " + a.Command
	}
	return string(a.Op) + " " + a.User
}

// runRoot runs the actions as root: in this process when it already is
// root, otherwise in `sudo lodestar __root` (sudo was unlocked beforehand).
func runRoot(req request, o Output) (*result, error) {
	if os.Geteuid() == 0 {
		return rootRun(req, o)
	}
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	req.Log = o.Log.Path()
	data, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	cmd := exec.Command("sudo", "-n", self, RootCommand)
	cmd.Stdin = bytes.NewReader(data)
	cmd.Stderr = o.Term // the root process logs itself
	stdout, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("the root part failed: %w", err)
	}
	var res result
	if err := json.Unmarshal(stdout, &res); err != nil {
		return nil, fmt.Errorf("the root part answered %q: %w", stdout, err)
	}
	return &res, nil
}

// RootMain is the root process: it reads a request on stdin, carries it out
// with progress on stderr, and writes the result on stdout.
func RootMain() error {
	if os.Geteuid() != 0 {
		return errors.New(RootCommand + " must run as root")
	}
	var req request
	if err := json.NewDecoder(os.Stdin).Decode(&req); err != nil {
		return err
	}
	o := Output{Term: os.Stderr}
	if req.Log != "" {
		if l, err := runlog.Append(req.Log); err == nil {
			o.Log = l
			defer l.Close()
		}
	}
	res, err := rootRun(req, o)
	if res != nil {
		json.NewEncoder(os.Stdout).Encode(res)
	}
	if err != nil {
		o.Log.Printf("lodestar (root): %v\n", err)
	}
	return err
}

func rootRun(req request, o Output) (*result, error) {
	out := o.progress()
	res := &result{PreNumber: req.PreNumber}
	if req.Snapper {
		n, err := snapper("--type", "pre", "--print-number", "--cleanup-algorithm", "number", "--description", "lodestar apply")
		if err != nil {
			fmt.Fprintln(out, "warning: no snapper snapshot:", err)
		}
		res.PreNumber = n
	}
	path := req.Root + state.SystemPath
	st, err := state.Load(path)
	if err != nil {
		return res, err
	}
	e := &env{root: req.Root, repo: req.Repo, user: req.User, home: req.Home, st: st, out: out, cmdOut: o.commandOut()}
	runErr := runAll(e, req.Actions)
	if len(req.Actions) > 0 {
		if err := st.Save(path); err != nil {
			runErr = errors.Join(runErr, err)
		}
	}
	if req.PreNumber > 0 {
		if _, err := snapper("--type", "post", "--pre-number", strconv.Itoa(req.PreNumber), "--cleanup-algorithm", "number", "--description", "lodestar apply"); err != nil {
			fmt.Fprintln(out, "warning: no snapper post snapshot:", err)
		}
	}
	return res, runErr
}

func snapperConfigured() bool {
	_, err := os.Stat("/etc/snapper/configs/root")
	_, err2 := exec.LookPath("snapper")
	return err == nil && err2 == nil
}

func snapper(args ...string) (int, error) {
	out, err := exec.Command("snapper", append([]string{"-c", "root", "create"}, args...)...).Output()
	if err != nil {
		return 0, err
	}
	n, _ := strconv.Atoi(strings.TrimSpace(string(out)))
	return n, nil
}

// HoldSudo asks for the password, unless sudo's ticket is still valid, and
// keeps the ticket fresh until stop is called: every sudo of the run (ours,
// makepkg's, yay's) uses it. The log tells whether it asked.
func HoldSudo(log *runlog.Log) (stop func(), err error) {
	if exec.Command("sudo", "-n", "-v").Run() == nil {
		log.Printf("(sudo: still unlocked)\n")
	} else {
		log.Printf("(sudo: asked for the password)\n")
		cmd := exec.Command("sudo", "-v", "-p", "[lodestar] password for %u: ")
		cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stderr, os.Stderr
		if err := cmd.Run(); err != nil {
			return nil, fmt.Errorf("sudo: %w", err)
		}
	}
	done := make(chan struct{})
	go func() {
		t := time.NewTicker(time.Minute)
		defer t.Stop()
		for {
			select {
			case <-done:
				return
			case <-t.C:
				exec.Command("sudo", "-n", "-v").Run()
			}
		}
	}()
	return func() { close(done) }, nil
}
