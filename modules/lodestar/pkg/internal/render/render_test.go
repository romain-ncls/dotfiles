package render

import (
	"errors"
	"os"
	"path/filepath"
	"testing"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
)

type fakeFacts map[string]string

func (f fakeFacts) Fact(name string) (string, error) {
	if v, ok := f[name]; ok {
		return v, nil
	}
	return "", errors.New("unknown fact " + name)
}

type fakeSecrets map[string]string

func (f fakeSecrets) Secret(item, field string) (string, error) { return f[item+"/"+field], nil }

func TestRender(t *testing.T) {
	dir := t.TempDir()
	home := filepath.Join(dir, "home")
	os.MkdirAll(filepath.Join(home, ".ssh"), 0o755)
	os.WriteFile(filepath.Join(home, ".ssh/id.pub"), []byte("ssh-ed25519 AAAA"), 0o644)
	c := &config.Config{Host: "box", User: config.User{Name: "romain"}, Vars: map[string]string{"email": "me@x"}}
	r := New(c, home, "", fakeFacts{"esp-uuid": "ABCD"}, fakeSecrets{"wifi/password": "hunter2"})

	write := func(name, text string) string {
		p := filepath.Join(dir, name)
		os.WriteFile(p, []byte(text), 0o644)
		return p
	}
	for _, tc := range []struct {
		text, want string
		secret     bool
	}{
		{`{{ .vars.email }} on {{ .host }} as {{ .user.name }}`, "me@x on box as romain", false},
		{`UUID={{ fact "esp-uuid" }}`, "UUID=ABCD", false},
		{`{{ file "~/.ssh/id.pub" }}|{{ file "~/.ssh/missing" }}`, "ssh-ed25519 AAAA|", false},
		{`psk={{ bitwarden "wifi" "password" }}`, "psk=hunter2", true},
	} {
		out, secret, err := r.Render(write("t.tmpl", tc.text))
		if err != nil {
			t.Errorf("%s: %v", tc.text, err)
			continue
		}
		if string(out) != tc.want || secret != tc.secret {
			t.Errorf("%s = %q (secret %v), want %q (secret %v)", tc.text, out, secret, tc.want, tc.secret)
		}
	}
	if _, _, err := r.Render(write("bad.tmpl", `{{ .vars.nope }}`)); err == nil {
		t.Error("a missing variable should be an error")
	}
	if err := Parse(write("syntax.tmpl", `{{ if }}`)); err == nil {
		t.Error("Parse should reject a syntax error")
	}
}
