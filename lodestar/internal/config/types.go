// Package config reads a host and its modules from the repo and merges them
// into one description of the machine.
package config

import "strings"

// Module is what a module.yaml declares. A host.yaml can declare the same
// things, and its values win over the modules'.
type Module struct {
	// Packages from the Arch repositories or the AUR. Local packages are not
	// listed here: a module's pkg/ folder installs its own.
	Packages []string `yaml:"packages,omitempty"`
	// System units to enable.
	Services []string `yaml:"services,omitempty"`
	// User units to enable for every user (systemctl --global enable).
	UserServices []string `yaml:"user-services,omitempty"`
	// Options for the files of the module's system/ and home/ folders, and
	// links. Keys are target paths: /etc/… or ~/…
	Files map[string]FileOptions `yaml:"files,omitempty"`
	// Paths that drift never reports, as globs (/etc/ssl/certs/*).
	Ignore []string `yaml:"ignore,omitempty"`
}

// FileOptions changes how a file is installed, or declares a link.
type FileOptions struct {
	// Mode in octal, like 0440. Default 0644, or 0755 for a file that is
	// executable in git.
	Mode Mode `yaml:"mode,omitempty"`
	// Owner of a system file. Default root.
	Owner string `yaml:"owner,omitempty"`
	// Group of a system file. Default root.
	Group string `yaml:"group,omitempty"`
	// Command run on the new file before it replaces the live one; {} is the
	// new file's path. Example: visudo -cf {}
	Check string `yaml:"check,omitempty"`
	// Command run after the file changed.
	Then string `yaml:"then,omitempty"`
	// Makes the target a link to this path, relative to the module folder.
	// For things edited in place, like mpv's config.
	Link string `yaml:"link,omitempty"`
}

// Host is a host.yaml: a module plus the settings only a host has.
type Host struct {
	// Modules of this host, in order. A later module's single values win
	// over an earlier one's; the host's own win over all of them.
	Modules []string `yaml:"modules"`
	// Variables for templates: {{ .vars.email }}.
	Vars map[string]string `yaml:"vars,omitempty"`
	// The login user.
	User User `yaml:"user"`
	// Settings read only by `lodestar install`.
	Install *Install `yaml:"install,omitempty"`

	Module `yaml:",inline"`
}

// User is the machine's login user.
type User struct {
	Name string `yaml:"name"`
	// Login shell, e.g. /usr/bin/fish.
	Shell string `yaml:"shell,omitempty"`
	// Supplementary groups. Groups the user has beyond these show up in drift.
	Groups []string `yaml:"groups,omitempty"`
}

// Install describes the disk for `lodestar install`.
type Install struct {
	// The disk's name in /dev/disk/by-id. Any other disk is refused.
	Disk string `yaml:"disk"`
	// Size of the EFI system partition, e.g. 4GiB.
	ESP string `yaml:"esp"`
	// Put btrfs inside LUKS2.
	Encrypt bool `yaml:"encrypt,omitempty"`
	// Size of the swapfile in @swap, e.g. 32GiB. Empty for no swap.
	Swapfile string `yaml:"swapfile,omitempty"`
}

// Mode is a file mode in octal. It keeps the text as written: YAML would read
// an unquoted 0644 as the number 420.
type Mode string

// UnmarshalYAML takes the scalar's source text, quoted or not.
func (m *Mode) UnmarshalYAML(raw []byte) error {
	*m = Mode(strings.Trim(strings.TrimSpace(string(raw)), `"'`))
	return nil
}
