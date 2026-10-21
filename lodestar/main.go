// lodestar makes an Arch Linux machine match its description in the dotfiles
// repo: packages, system files, services, $HOME and KDE settings.
package main

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/render"
	"github.com/romain-ncls/dotfiles/lodestar/internal/schema"
)

type command struct {
	summary string
	run     func(o *options, args []string) error
}

var commands = map[string]command{
	"check":  {"validate a host's config without reading the machine", cmdCheck},
	"schema": {"regenerate the JSON Schemas in schema/", cmdSchema},
}

// options are the flags every command takes.
type options struct {
	repo string
	host string
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
