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

	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
	"github.com/romain-ncls/dotfiles/lodestar/internal/state"
)

// RootCommand is the hidden command the root process runs as.
const RootCommand = "__root"

// request is what the user process sends to the root process on stdin.
type request struct {
	Root    string         `json:"root"`
	Actions []*plan.Action `json:"actions"`
	// Snapper: "pre" takes the pre snapshot before the actions; a non-zero
	// PreNumber takes the matching post snapshot after them.
	Snapper   bool `json:"snapper"`
	PreNumber int  `json:"pre_number"`
}

type result struct {
	PreNumber int `json:"pre_number"`
}

// Apply carries out the plan. out receives the progress.
func Apply(p *plan.Plan, out io.Writer) error {
	byPhase := map[plan.Phase][]*plan.Action{}
	for _, a := range p.Actions {
		byPhase[a.Phase] = append(byPhase[a.Phase], a)
	}

	if p.HasRoot() && os.Geteuid() != 0 {
		stop, err := holdSudo()
		if err != nil {
			return err
		}
		defer stop()
	}

	snap := p.HasRoot() && p.Root == "" && snapperConfigured()
	pre := 0
	if len(byPhase[plan.PhasePackages]) > 0 || snap {
		res, err := runRoot(request{Root: p.Root, Actions: byPhase[plan.PhasePackages], Snapper: snap}, out)
		if err != nil {
			return err
		}
		pre = res.PreNumber
	}
	if aur := byPhase[plan.PhaseAUR]; len(aur) > 0 {
		e := &env{root: p.Root, st: &state.State{Files: map[string]state.File{}}, out: out}
		for _, a := range aur {
			fmt.Fprintf(out, "==> yay -S %s\n", strings.Join(a.Names, " "))
			if err := e.do(a); err != nil {
				return err
			}
		}
	}
	if len(byPhase[plan.PhaseSystem]) > 0 || pre > 0 {
		if _, err := runRoot(request{Root: p.Root, Actions: byPhase[plan.PhaseSystem], PreNumber: pre}, out); err != nil {
			return err
		}
	}
	if home := byPhase[plan.PhaseHome]; len(home) > 0 {
		return runHome(p, home, out)
	}
	return nil
}

// runHome carries out the home phase as the user, and saves the home state.
func runHome(p *plan.Plan, actions []*plan.Action, out io.Writer) error {
	path := p.Root + filepath.Join(p.Home, state.HomePath)
	st, err := state.Load(path)
	if err != nil {
		return err
	}
	e := &env{root: p.Root, st: st, out: out}
	if os.Geteuid() == 0 { // install, or a container: home files go to the user
		u, err := user.Lookup(p.User)
		if err != nil {
			return err
		}
		uid, _ := strconv.Atoi(u.Uid)
		gid, _ := strconv.Atoi(u.Gid)
		e.owner = &account{uid, gid}
	}
	runErr := runAll(e, actions, out)
	if err := st.Save(path); err != nil {
		return errors.Join(runErr, err)
	}
	if e.owner != nil {
		for d := filepath.Dir(path); strings.HasPrefix(d, p.Root+p.Home+"/"); d = filepath.Dir(d) {
			os.Chown(d, e.owner.uid, e.owner.gid)
		}
		os.Chown(path, e.owner.uid, e.owner.gid)
	}
	return runErr
}

func runAll(e *env, actions []*plan.Action, out io.Writer) error {
	for _, a := range actions {
		fmt.Fprintln(out, "==> "+label(a))
		if err := e.do(a); err != nil {
			return fmt.Errorf("%s: %w", label(a), err)
		}
	}
	return nil
}

func label(a *plan.Action) string {
	switch {
	case a.User != "":
		return string(a.Op) + " " + a.User
	case a.Display != "":
		return string(a.Op) + " " + a.Display
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
func runRoot(req request, out io.Writer) (*result, error) {
	if os.Geteuid() == 0 {
		return rootRun(req, out)
	}
	self, err := os.Executable()
	if err != nil {
		return nil, err
	}
	data, err := json.Marshal(req)
	if err != nil {
		return nil, err
	}
	cmd := exec.Command("sudo", "-n", self, RootCommand)
	cmd.Stdin = bytes.NewReader(data)
	cmd.Stderr = out
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
	res, err := rootRun(req, os.Stderr)
	if res != nil {
		json.NewEncoder(os.Stdout).Encode(res)
	}
	return err
}

func rootRun(req request, out io.Writer) (*result, error) {
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
	e := &env{root: req.Root, st: st, out: out}
	runErr := runAll(e, req.Actions, out)
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

// holdSudo asks for the password once and keeps sudo's ticket fresh until
// stop is called.
func holdSudo() (stop func(), err error) {
	cmd := exec.Command("sudo", "-v", "-p", "[lodestar] password for %u: ")
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stderr, os.Stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("sudo: %w", err)
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
