// lodestar makes an Arch Linux machine match its description in the dotfiles
// repo: packages, system files, services, $HOME and KDE settings.
package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"os/user"
	"path/filepath"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/romain-ncls/dotfiles/lodestar/internal/apply"
	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/drift"
	"github.com/romain-ncls/dotfiles/lodestar/internal/install"
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
	"apply":   {"make the machine match the repo (--system or --home: only that part)", cmdApply},
	"install": {"install a host on a blank disk, from the Arch live USB", cmdInstall},
	"check":   {"validate a host's config without reading the machine", cmdCheck},
	"drift":   {"list what is on the machine but not in the repo", cmdDrift},
	"kde":     {"review: keep, ignore or undo KDE changes; watch: show the keys one change sets", cmdKDE},
	"plan":    {"show what apply would change", cmdPlan},
	"prune":   {"remove the packages the repo doesn't declare", cmdPrune},
	"upgrade": {"yay -Syu without the local packages, then rebuild those that need it and apply", cmdUpgrade},
	"schema":  {"regenerate the JSON Schemas in schema/", cmdSchema},
}

// options are the flags every command takes.
type options struct {
	repo   string
	host   string
	yes    bool
	list   bool
	system bool
	home   bool
	disk   string
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
	fs.BoolVar(&o.list, "list", false, "kde review: print the changes as YAML instead of asking")
	fs.BoolVar(&o.system, "system", false, "apply: only packages and the system")
	fs.BoolVar(&o.home, "home", false, "apply: only $HOME")
	fs.StringVar(&o.disk, "disk", "", "install: this disk instead of the host's install.disk (tests)")
	// Flags may come after the arguments too: lodestar kde review --list.
	var args []string
	rest := os.Args[2:]
	for {
		fs.Parse(rest)
		if fs.NArg() == 0 {
			break
		}
		args = append(args, fs.Arg(0))
		rest = fs.Args()[1:]
	}

	if err := cmd.run(o, args); err != nil {
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
		// Under sudo, the repo is still the one in the user's home.
		if name := os.Getenv("SUDO_USER"); os.Geteuid() == 0 && name != "" && name != "root" {
			if u, err := user.Lookup(name); err == nil {
				home = u.HomeDir
			}
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
	for _, w := range nameClashes(c) {
		fmt.Println(style().Yellow("!") + " " + w)
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
		if strings.HasPrefix(p, "(") {
			fmt.Println(p)
			continue
		}
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
	return planWith(c, nil)
}

func planWith(c *config.Config, rebuild map[string]bool) (*plan.Plan, error) {
	return plan.Compute(plan.Input{
		Rebuild: rebuild,
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
		printNotes(p)
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
	if o.system != o.home {
		p.Only(o.system)
	}
	return applyPlan(o, p)
}

func cmdInstall(o *options, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: lodestar install <host> [--repo DIR] [--disk /dev/…] [--yes]")
	}
	repo, err := o.repoDir()
	if err != nil {
		return err
	}
	return install.Run(install.Options{Repo: repo, Host: args[0], Disk: o.disk, Yes: o.yes, Out: os.Stdout})
}

func applyPlan(o *options, p *plan.Plan) error {
	if p.Empty() {
		fmt.Println("Nothing to do: the machine matches the repo.")
		printNotes(p)
		if len(p.Actions) > 0 { // hooks that run on every apply
			return apply.Apply(p, os.Stdout)
		}
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
		ui.PrintUnreadable(os.Stdout, r.Unreadable, style())
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

func printNotes(p *plan.Plan) {
	for _, n := range p.Notes {
		fmt.Println(style().Yellow("!") + " " + n)
	}
}

// cmdUpgrade updates the system with yay, keeping yay away from the local
// packages (an AUR package of the same name would replace them), then
// rebuilds the local packages that need it and applies.
func cmdUpgrade(o *options, args []string) error {
	c, err := o.load()
	if err != nil {
		return err
	}
	before, err := planFor(c)
	if err != nil {
		return err
	}
	yay := []string{"yay", "-Syu"}
	if len(before.LocalNames) > 0 {
		yay = append(yay, "--ignore", strings.Join(before.LocalNames, ","))
	}
	cmd := exec.Command(yay[0], yay[1:]...)
	cmd.Stdin, cmd.Stdout, cmd.Stderr = os.Stdin, os.Stdout, os.Stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("yay: %w", err)
	}

	// checkrebuild (rebuild-detector) lists packages whose libraries changed.
	rebuild := map[string]bool{}
	if out, err := exec.Command("checkrebuild").Output(); err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			if f := strings.Fields(line); len(f) > 0 {
				name := f[len(f)-1]
				if slices.Contains(before.LocalNames, name) {
					rebuild[name] = true
				}
			}
		}
	}
	p, err := planWith(c, rebuild)
	if err != nil {
		return err
	}
	return applyPlan(o, p)
}

// nameClashes warns about local packages named like a repo or AUR package:
// yay would replace them with that package once its version is higher.
func nameClashes(c *config.Config) []string {
	var names []string
	for _, lp := range c.LocalPackages {
		names = append(names, lp.Names...)
	}
	if len(names) == 0 {
		return nil
	}
	var out []string
	if repos, err := (machine.Local{}).InRepos(); err == nil {
		for _, n := range names {
			if repos[n] {
				out = append(out, fmt.Sprintf("local package %s has the name of a repo package", n))
			}
		}
	}
	q := url.Values{}
	for _, n := range names {
		q.Add("arg[]", n)
	}
	client := http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://aur.archlinux.org/rpc/v5/info?" + q.Encode())
	if err != nil {
		return out // offline: no AUR check
	}
	defer resp.Body.Close()
	var info struct {
		Results []struct {
			Name, Version, Description string
		} `json:"results"`
	}
	if json.NewDecoder(resp.Body).Decode(&info) == nil {
		for _, r := range info.Results {
			out = append(out, fmt.Sprintf("local package %s has the name of an AUR package (%s, %s): yay -Syu would replace it once that version is higher", r.Name, r.Version, r.Description))
		}
	}
	return out
}
