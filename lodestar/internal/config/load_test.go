package config

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// writeRepo builds a repo from path -> content. A content starting with "->"
// makes a symlink; a path ending in "*" makes an executable file.
func writeRepo(t *testing.T, files map[string]string) string {
	t.Helper()
	repo := t.TempDir()
	for p, content := range files {
		mode := os.FileMode(0o644)
		if strings.HasSuffix(p, "*") {
			p, mode = strings.TrimSuffix(p, "*"), 0o755
		}
		full := filepath.Join(repo, p)
		if err := os.MkdirAll(filepath.Dir(full), 0o755); err != nil {
			t.Fatal(err)
		}
		if target, ok := strings.CutPrefix(content, "->"); ok {
			if err := os.Symlink(target, full); err != nil {
				t.Fatal(err)
			}
			continue
		}
		if err := os.WriteFile(full, []byte(content), mode); err != nil {
			t.Fatal(err)
		}
	}
	return repo
}

const hostYAML = `
modules:
  - base
  - git
user:
  name: romain
  shell: /usr/bin/fish
  groups:
    - wheel
vars:
  email: me@example.com
packages:
  - htop
`

func TestLoadMerges(t *testing.T) {
	repo := writeRepo(t, map[string]string{
		"hosts/box/host.yaml":              hostYAML,
		"hosts/box/system/etc/hostname":    "box\n",
		"hosts/box/system/etc/locale.conf": "LANG=fr_FR.UTF-8\n", // overrides base
		"modules/base/module.yaml": `
packages:
  - base
  - htop
services:
  - systemd-timesyncd.service
files:
  /etc/sudoers:
    mode: "0440"
    check: "visudo -cf {}"
ignore:
  - /etc/ssl/certs/*
`,
		"modules/base/system/etc/locale.conf":   "LANG=en_US.UTF-8\n",
		"modules/base/system/etc/sudoers":       "%wheel ALL=(ALL:ALL) ALL\n",
		"modules/base/system/etc/localtime":     "->/usr/share/zoneinfo/Europe/Paris",
		"modules/base/system/usr/local/bin/hi*": "#!/bin/sh\necho hi\n",
		"modules/git/module.yaml": `
packages:
  - git
files:
  ~/.config/mpv:
    link: mpv-config
`,
		"modules/git/mpv-config/mpv.conf":  "",
		"modules/git/home/.gitconfig.tmpl": "[user]\n\temail = {{ .vars.email }}\n",
		"modules/git/pkg/PKGBUILD":         "pkgname=git-tools\npkgver=1\n",
	})

	c, err := Load(repo, "box")
	if err != nil {
		t.Fatal(err)
	}

	var pkgs []string
	for _, p := range c.Packages {
		pkgs = append(pkgs, p.Name+"<"+p.From)
	}
	if got, want := strings.Join(pkgs, " "), "base<base htop<base git<git"; got != want {
		t.Errorf("packages = %s, want %s", got, want)
	}
	if len(c.LocalPackages) != 1 || c.LocalPackages[0].Names[0] != "git-tools" {
		t.Errorf("local packages = %+v", c.LocalPackages)
	}

	byTarget := map[string]*File{}
	for _, f := range c.Files {
		byTarget[f.Target] = f
	}
	for target, check := range map[string]func(*File) bool{
		"/etc/hostname":         func(f *File) bool { return f.From == "host box" },
		"/etc/locale.conf":      func(f *File) bool { return f.From == "host box" },
		"/etc/sudoers":          func(f *File) bool { return f.Mode() == 0o440 && f.Opts.Check != "" },
		"/etc/localtime":        func(f *File) bool { return f.Link == "/usr/share/zoneinfo/Europe/Paris" },
		"/usr/local/bin/hi":     func(f *File) bool { return f.Mode() == 0o755 },
		"~/.gitconfig":          func(f *File) bool { return f.Template && f.Scope == Home },
		"~/.config/mpv":         func(f *File) bool { return f.Link == filepath.Join(repo, "modules/git/mpv-config") },
		"/etc/locale.conf.tmpl": nil,
	} {
		f, ok := byTarget[target]
		if check == nil {
			if ok {
				t.Errorf("%s should not exist", target)
			}
			continue
		}
		if !ok {
			t.Errorf("%s missing", target)
			continue
		}
		if !check(f) {
			t.Errorf("%s: unexpected %+v", target, f)
		}
	}
}

func TestLoadErrors(t *testing.T) {
	base := map[string]string{
		"hosts/box/host.yaml": "modules:\n  - a\n  - b\nuser:\n  name: romain\n",
		"modules/a/.keep":     "",
		"modules/b/.keep":     "",
	}
	for name, tc := range map[string]struct {
		files map[string]string
		want  string
	}{
		"unknown key": {map[string]string{"modules/a/module.yaml": "pakages:\n  - x\n"}, "unknown field"},
		"collision": {map[string]string{
			"modules/a/system/etc/x": "a",
			"modules/b/system/etc/x": "b",
		}, "provided by both"},
		"options without file": {map[string]string{"modules/a/module.yaml": "files:\n  /etc/nope:\n    mode: \"0600\"\n"}, "no such file"},
		"bad mode":             {map[string]string{"modules/a/module.yaml": "files:\n  /etc/x:\n    mode: 0900\n", "modules/a/system/etc/x": ""}, "not an octal mode"},
		"bad unit":             {map[string]string{"modules/a/module.yaml": "services:\n  - bluetooth\n"}, "not a valid unit"},
		"missing module":       {map[string]string{"hosts/box/host.yaml": "modules:\n  - zzz\nuser:\n  name: r\n"}, "does not exist"},
		"link escapes":         {map[string]string{"modules/a/module.yaml": "files:\n  ~/x:\n    link: ../b\n"}, "must stay inside"},
		"options on other's file": {map[string]string{
			"modules/a/system/etc/x": "",
			"modules/b/module.yaml":  "files:\n  /etc/x:\n    mode: \"0600\"\n",
		}, "belongs to a"},
	} {
		t.Run(name, func(t *testing.T) {
			files := map[string]string{}
			for k, v := range base {
				files[k] = v
			}
			for k, v := range tc.files {
				files[k] = v
			}
			_, err := Load(writeRepo(t, files), "box")
			if err == nil || !strings.Contains(err.Error(), tc.want) {
				t.Fatalf("err = %v, want it to contain %q", err, tc.want)
			}
		})
	}
}

// YAML reads an unquoted 0644 as the number 420; the mode must keep its text.
func TestModeQuotesOptional(t *testing.T) {
	for _, mode := range []string{`0640`, `"0640"`, `'0640'`, `640`} {
		repo := writeRepo(t, map[string]string{
			"hosts/box/host.yaml":    "modules:\n  - a\nuser:\n  name: r\n",
			"modules/a/module.yaml":  "files:\n  /etc/x:\n    mode: " + mode + "\n",
			"modules/a/system/etc/x": "",
		})
		c, err := Load(repo, "box")
		if err != nil {
			t.Fatalf("mode %s: %v", mode, err)
		}
		if got := c.Files[0].Mode(); got != 0o640 {
			t.Errorf("mode %s read as %o", mode, got)
		}
	}
}
