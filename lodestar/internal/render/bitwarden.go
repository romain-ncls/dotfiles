package render

import (
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// Bitwarden reads secrets with the official CLI. It unlocks the vault the
// first time a template needs a secret, and keeps the session for this run
// only.
type Bitwarden struct {
	// Interactive allows asking for the master password on the terminal.
	Interactive bool

	session string
	items   map[string]*bwItem
}

type bwItem struct {
	Notes string `json:"notes"`
	Login *struct {
		Username string `json:"username"`
		Password string `json:"password"`
	} `json:"login"`
	Fields []struct {
		Name  string `json:"name"`
		Value string `json:"value"`
	} `json:"fields"`
}

// Secret returns field of item: password, username, notes, or the name of a
// custom field.
func (b *Bitwarden) Secret(item, field string) (string, error) {
	it, err := b.item(item)
	if err != nil {
		return "", err
	}
	switch field {
	case "password", "username":
		if it.Login == nil {
			return "", fmt.Errorf("bitwarden: %q has no login", item)
		}
		if field == "password" {
			return it.Login.Password, nil
		}
		return it.Login.Username, nil
	case "notes":
		return it.Notes, nil
	}
	for _, f := range it.Fields {
		if f.Name == field {
			return f.Value, nil
		}
	}
	return "", fmt.Errorf("bitwarden: %q has no field %q", item, field)
}

func (b *Bitwarden) item(name string) (*bwItem, error) {
	if it, ok := b.items[name]; ok {
		return it, nil
	}
	if err := b.unlock(); err != nil {
		return nil, err
	}
	cmd := exec.Command("bw", "get", "item", name)
	cmd.Env = append(os.Environ(), "BW_SESSION="+b.session)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		return nil, fmt.Errorf("bitwarden: %s: %s", name, strings.TrimSpace(stderr.String()))
	}
	var it bwItem
	if err := json.Unmarshal(out, &it); err != nil {
		return nil, fmt.Errorf("bitwarden: %s: %w", name, err)
	}
	if b.items == nil {
		b.items = map[string]*bwItem{}
	}
	b.items[name] = &it
	return &it, nil
}

func (b *Bitwarden) unlock() error {
	if b.session != "" {
		return nil
	}
	if s := os.Getenv("BW_SESSION"); s != "" {
		b.session = s
		return nil
	}
	if _, err := exec.LookPath("bw"); err != nil {
		return errors.New("bitwarden: the bw command is not installed")
	}
	out, err := exec.Command("bw", "status").Output()
	if err != nil {
		return fmt.Errorf("bitwarden: bw status: %w", err)
	}
	var st struct {
		Status string `json:"status"`
	}
	if err := json.Unmarshal(out, &st); err != nil {
		return fmt.Errorf("bitwarden: bw status: %w", err)
	}
	if st.Status == "unauthenticated" {
		return errors.New("bitwarden: not logged in (run bw login once)")
	}
	if !b.Interactive {
		return errors.New("bitwarden: the vault is locked, and there is no terminal to ask for the master password")
	}
	fmt.Fprintln(os.Stderr, "A template needs a Bitwarden secret.")
	cmd := exec.Command("bw", "unlock", "--raw")
	cmd.Stdin, cmd.Stderr = os.Stdin, os.Stderr
	session, err := cmd.Output()
	if err != nil || len(bytes.TrimSpace(session)) == 0 {
		return errors.New("bitwarden: unlock failed")
	}
	b.session = string(bytes.TrimSpace(session))
	return nil
}
