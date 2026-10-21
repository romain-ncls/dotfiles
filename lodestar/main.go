// lodestar makes an Arch Linux machine match its description in the dotfiles
// repo: packages, system files, services, $HOME and KDE settings.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/apply"
	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/drift"
	"github.com/romain-ncls/dotfiles/lodestar/internal/machine"
	"github.com/romain-ncls/dotfiles/lodestar/internal/plan"
	"github.com/romain-ncls/dotfiles/lodestar/internal/render"
	"github.com/romain-ncls/dotfiles/lodestar/internal/schema"
	"github.com/romain-ncls/dotfiles/lodestar/internal/ui"
)

type command struct {
	summary string
	run     func(o *options, args []string) error
}

var commands = map[string]command{
	"apply":  {"make the machine match the repo", cmdApply},
	"check":  {"validate a host's config without reading the machine", cmdCheck},
	"drift":  {"list what is on the machine but not in the repo", cmdDrift},
	"plan":   {"show what apply would change", cmdPlan},
	"prune":  {"remove the packages the repo doesn't declare", cmdPrune},
	"schema": {"regenerate the JSON Schemas in schema/", cmdSchema},
}

// options are the flags every command takes.
type options struct {
	repo string
	host string
	yes  bool
}

func usage() {
	fmt.Fprintln(os.Stderr, "usage: lodestar <command> [--repo DIR] [--host NAME] [args]\n\ncommands:")
	names := make([]string, 0, len(commands))
	for n := range commands {
		names = append(names, n)
	}
	sort.Strings(names)
	for _, n := range names {
		fmt.Fprintf(os.Stderr, "  %-8s %s\n", n, commands[n].summary)
	}
}

func main() {
	if len(os.Args) == 2 && os.Args[1] == apply.RootCommand {
		if err := apply.RootMain(); err != nil {
			fmt.Fprintln(os.Stderr, "lodestar (root):", err)
			os.Exit(1)
		}
		return
	}
	if len(os.Args) < 2 || os.Args[1] == "-h" || os.Args[1] == "--help" || os.Args[1] == "help" {
		usage()
		os.Exit(2)
	}
	cmd, ok := commands[os.Args[1]]
	if !ok {
		fmt.Fprintf(os.Stderr, "lodestar: unknown command %q\n\n", os.Args[1])
		usage()
		os.Exit(2)
	}

	o := &options{}
	fs := flag.NewFlagSet("lodestar "+os.Args[1], flag.ExitOnError)
	fs.StringVar(&o.repo, "repo", "", "the dotfiles repo (default $LODESTAR_REPO, then ~/dotfiles)")
	fs.StringVar(&o.host, "host", "", "the host to use (default: this machine's hostname)")
	fs.BoolVar(&o.yes, "yes", false, "apply without asking")
	fs.Parse(os.Args[2:])

	if err := cmd.run(o, fs.Args()); err != nil {
		var exit exitError
		if errors.As(err, &exit) {
			os.Exit(int(exit))
		}
		fmt.Fprintln(os.Stderr, "lodestar:", err)
		os.Exit(1)
	}
}

// exitError ends lodestar with a status and no message: the command already
// printed what was wrong.
type exitError int

func (e exitError) Error() string { return fmt.Sprintf("exit status %d", int(e)) }

func (o *options) repoDir() (string, error) {
	dir := o.repo
	if dir == "" {
		dir = os.Getenv("LODESTAR_REPO")
	}
	if dir == "" {
		home, err := os.UserHomeDir()
		if err != nil {
			return "", err
		}
		dir = filepath.Join(home, "dotfiles")
	}
	dir, err := filepath.Abs(dir)
	if err != nil {
		return "", err
	}
	if _, err := os.Stat(filepath.Join(dir, "hosts")); err != nil {
		return "", fmt.Errorf("%s has no hosts/ folder: set --repo or $LODESTAR_REPO", dir)
	}
	return dir, nil
}

func (o *options) hostName() (string, error) {
	if o.host != "" {
		return o.host, nil
	}
	return os.Hostname()
}

func (o *options) load() (*config.Config, error) {
	repo, err := o.repoDir()
	if err != nil {
		return nil, err
	}
	host, err := o.hostName()
	if err != nil {
		return nil, err
	}
	return config.Load(repo, host)
}

func cmdCheck(o *options, args []string) error {
	c, err := o.load()
	if err != nil {
		return err
	}
	if err := checkTemplates(c); err != nil {
		return err
	}
	fmt.Printf("%s: %d modules, %d packages, %d local packages, %d files, %d units: OK\n",
		c.Host, len(c.Modules), len(c.Packages), len(c.LocalPackages), len(c.Files),
		len(c.Services)+len(c.UserServices))
	return nil
}

func cmdSchema(o *options, args []string) error {
	repo, err := o.repoDir()
	if err != nil {
		return err
	}
	written, err := schema.Write(repo)
	if err != nil {
		return err
	}
	for _, p := range written {
		r, _ := filepath.Rel(repo, p)
		fmt.Println("wrote", r)
	}
	return nil
}

// checkTemplates parses every template, without running it.
func checkTemplates(c *config.Config) error {
	var errs []string
	for _, f := range c.Files {
		if !f.Template {
			continue
		}
		if err := render.Parse(f.Source); err != nil {
			errs = append(errs, err.Error())
		}
	}
	if len(errs) > 0 {
		return errors.New(strings.Join(errs, "\n"))
	}
	return nil
}

func (o *options) plan() (*plan.Plan, error) {
	c, err := o.load()
	if err != nil {
		return nil, err
	}
	return planFor(c)
}

func planFor(c *config.Config) (*plan.Plan, error) {
	return plan.Compute(plan.Input{
		Config:  c,
		Machine: machine.Local{},
		Facts:   &render.MachineFacts{},
		Secrets: &render.Bitwarden{Interactive: ui.IsTerminal(os.Stdin)},
	})
}

func style() ui.Style {
	return ui.Style{Color: ui.IsTerminal(os.Stdout) && os.Getenv("NO_COLOR") == ""}
}

func cmdPlan(o *options, args []string) error {
	p, err := o.plan()
	if err != nil {
		return err
	}
	if p.Empty() {
		fmt.Println("Nothing to do: the machine matches the repo.")
		return nil
	}
	ui.PrintPlan(os.Stdout, p, style())
	return nil
}

func cmdApply(o *options, args []string) error {
	p, err := o.plan()
	if err != nil {
		return err
	}
	if p.Empty() {
		fmt.Println("Nothing to do: the machine matches the repo.")
		return nil
	}
	ui.PrintPlan(os.Stdout, p, style())
	fmt.Println()
	if !o.yes && !ui.Confirm("Apply?") {
		return exitError(1)
	}
	if err := apply.Apply(p, os.Stdout); err != nil {
		return err
	}
	fmt.Println(style().Green("Done."))
	return nil
}

func cmdDrift(o *options, args []string) error {
	c, err := o.load()
	if err != nil {
		return err
	}
	p, err := planFor(c)
	if err != nil {
		return err
	}
	r, err := drift.Find(c, machine.Local{}, p, "")
	if err != nil {
		return err
	}
	if r.Empty() {
		fmt.Println("No drift: the machine matches the repo.")
		if len(r.Unreadable) > 0 {
			fmt.Printf("(%d paths need root to check: sudo lodestar drift)\n", len(r.Unreadable))
		}
		return nil
	}
	ui.PrintDrift(os.Stdout, r, style())
	return exitError(1)
}

// cmdPrune marks the undeclared explicit packages as dependencies, then lets
// pacman remove every orphan: packages still needed by declared ones stay.
func cmdPrune(o *options, args []string) error {
	c, err := o.load()
	if err != nil {
		return err
	}
	p, err := planFor(c)
	if err != nil {
		return err
	}
	r, err := drift.Find(c, machine.Local{}, p, "")
	if err != nil {
		return err
	}
	if len(r.UndeclaredPackages) == 0 {
		fmt.Println("Every explicitly installed package is declared.")
	} else {
		s := style()
		fmt.Println(s.Bold("Installed by hand, not declared:"))
		for _, n := range r.UndeclaredPackages {
			fmt.Println("  " + s.Red("-") + " " + n)
		}
		fmt.Println(s.Dim("They become dependencies: pacman then removes those nothing else needs."))
		if !o.yes && !ui.Confirm("Continue?") {
			return exitError(1)
		}
		if err := sudo(append([]string{"pacman", "-D", "--asdeps"}, r.UndeclaredPackages...)...); err != nil {
			return err
		}
	}
	orphans, err := exec.Command("pacman", "-Qdtq").Output()
	names := strings.Fields(string(orphans))
	if err != nil || len(names) == 0 {
		fmt.Println("No orphans to remove.")
		return nil
	}
	cmd := []string{"pacman", "-Rns"}
	if o.yes {
		cmd = append(cmd, "--noconfirm")
	}
	return sudo(append(cmd, names...)...)
}

// sudo runs a command as root, on the terminal.
func sudo(args ...string) error {
	if os.Geteuid() != 0 {
		args = append([]string{"sudo"}, args...)
	}
	cmd := exec.Command(args[0], args[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	return cmd.Run()
}
