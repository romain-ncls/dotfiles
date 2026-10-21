package render

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
)

// MachineFacts reads facts with findmnt and lsblk, under root ("" on a
// running system, /mnt during an install).
type MachineFacts struct {
	Root  string
	cache map[string]string
}

var factNames = []string{"root-uuid", "root-luks-uuid", "esp-uuid"}

// Fact returns one of: root-uuid (the filesystem mounted at /),
// root-luks-uuid (the LUKS partition under /), esp-uuid (the filesystem at
// /boot).
func (m *MachineFacts) Fact(name string) (string, error) {
	if v, ok := m.cache[name]; ok {
		return v, nil
	}
	var v string
	var err error
	switch name {
	case "root-uuid":
		v, err = run("findmnt", "-no", "UUID", "--mountpoint", m.path("/"))
	case "esp-uuid":
		v, err = run("findmnt", "-no", "UUID", "--mountpoint", m.path("/boot"))
	case "root-luks-uuid":
		v, err = m.luksUUID()
	default:
		return "", fmt.Errorf("unknown fact %q (known: %s)", name, strings.Join(factNames, ", "))
	}
	if err != nil {
		return "", fmt.Errorf("fact %s: %w", name, err)
	}
	if v == "" {
		return "", fmt.Errorf("fact %s: not found on this machine", name)
	}
	if m.cache == nil {
		m.cache = map[string]string{}
	}
	m.cache[name] = v
	return v, nil
}

func (m *MachineFacts) path(p string) string {
	if m.Root == "" {
		return p
	}
	return filepath.Join(m.Root, p)
}

// luksUUID walks from the device mounted at / up to its LUKS partition.
func (m *MachineFacts) luksUUID() (string, error) {
	src, err := run("findmnt", "-no", "SOURCE", "--mountpoint", m.path("/"))
	if err != nil {
		return "", err
	}
	src, _, _ = strings.Cut(src, "[") // btrfs: /dev/mapper/root[/@]
	out, err := run("lsblk", "-s", "-n", "-r", "-o", "FSTYPE,UUID", src)
	if err != nil {
		return "", err
	}
	for _, line := range strings.Split(out, "\n") {
		if fstype, uuid, ok := strings.Cut(line, " "); ok && fstype == "crypto_LUKS" {
			return uuid, nil
		}
	}
	return "", fmt.Errorf("%s is not on a LUKS partition", src)
}

func run(name string, args ...string) (string, error) {
	out, err := exec.Command(name, args...).Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok && len(ee.Stderr) > 0 {
			return "", fmt.Errorf("%s: %s", name, strings.TrimSpace(string(ee.Stderr)))
		}
		return "", fmt.Errorf("%s: %w", name, err)
	}
	return strings.TrimSpace(string(out)), nil
}
