// Package render runs the .tmpl files: Go templates with the host's
// variables, facts read from the machine, other files, and Bitwarden secrets.
package render

import (
	"bytes"
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"text/template"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
)

// Facts gives values read from the machine, like a disk UUID.
type Facts interface {
	Fact(name string) (string, error)
}

// Secrets gives a field of a Bitwarden item.
type Secrets interface {
	Secret(item, field string) (string, error)
}

// Renderer runs templates for one host.
type Renderer struct {
	data    map[string]any
	facts   Facts
	secrets Secrets
	home    string // the user's home, for file "~/…"
	root    string // prefix for every path read ("" on a running system)
}

// New returns a Renderer for c. home is the user's home directory and root
// the prefix of the machine's filesystem ("" except during an install).
func New(c *config.Config, home, root string, facts Facts, secrets Secrets) *Renderer {
	groups := c.User.Groups
	if groups == nil {
		groups = []string{}
	}
	vars := c.Vars
	if vars == nil {
		vars = map[string]string{}
	}
	return &Renderer{
		data: map[string]any{
			"host": c.Host,
			"vars": vars,
			"user": map[string]any{"name": c.User.Name, "shell": c.User.Shell, "groups": groups, "home": home},
		},
		facts:   facts,
		secrets: secrets,
		home:    home,
		root:    root,
	}
}

// Render runs the template at path. secret is true when it used a Bitwarden
// secret, so the result must never be shown.
func (r *Renderer) Render(path string) (out []byte, secret bool, err error) {
	text, err := os.ReadFile(path)
	if err != nil {
		return nil, false, err
	}
	funcs := template.FuncMap{
		"fact": func(name string) (string, error) {
			if r.facts == nil {
				return "", errors.New("facts are not available here")
			}
			return r.facts.Fact(name)
		},
		"file": func(p string) (string, error) {
			data, err := os.ReadFile(r.root + r.expand(p))
			if errors.Is(err, fs.ErrNotExist) {
				return "", nil
			}
			return string(data), err
		},
		"bitwarden": func(item, field string) (string, error) {
			secret = true
			if r.secrets == nil {
				return "", ErrLocked
			}
			return r.secrets.Secret(item, field)
		},
	}
	t, err := template.New(filepath.Base(path)).Funcs(funcs).Option("missingkey=error").Parse(string(text))
	if err != nil {
		return nil, false, err
	}
	var buf bytes.Buffer
	if err := t.Execute(&buf, r.data); err != nil {
		return nil, secret, err
	}
	return buf.Bytes(), secret, nil
}

func (r *Renderer) expand(p string) string {
	if rest, ok := strings.CutPrefix(p, "~/"); ok {
		return filepath.Join(r.home, rest)
	}
	return p
}

// Parse checks a template's syntax without running it.
func Parse(path string) error {
	text, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	stub := func(...string) (string, error) { return "", nil }
	_, err = template.New(filepath.Base(path)).
		Funcs(template.FuncMap{"fact": stub, "file": stub, "bitwarden": stub}).
		Parse(string(text))
	if err != nil {
		return fmt.Errorf("%s: %w", path, err)
	}
	return nil
}
