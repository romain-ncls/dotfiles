// Package config reads a host and its modules from the repo and merges them
// into one description of the machine.
package config

import (
	"strings"

	"github.com/goccy/go-yaml"
)

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
	// Paths that drift never reports, as globs where * also matches /
	// (/etc/ssl/certs/*).
	Ignore []string `yaml:"ignore,omitempty"`

	// Ports to open. Declaring firewall: in any module turns the firewall on,
	// even with no port.
	Firewall *Firewall `yaml:"firewall,omitempty"`

	// KDE settings: file, then group (nested groups separated by /), then
	// key and value, written with kwriteconfig6. Only for files KDE also
	// writes itself; a file KDE only reads goes in home/.
	KDE map[string]map[string]map[string]Value `yaml:"kde,omitempty"`
	// KDE keys lodestar kde review never shows, as file/group/key globs
	// where * also matches /: dolphinrc/MainWindow/*
	KDEIgnore []string `yaml:"kde-ignore,omitempty"`
	// Breeze window decoration exceptions (breezerc). lodestar numbers the
	// entries of every module and owns the whole list. Keys as in breezerc:
	// ExceptionPattern, ExceptionType, HideTitleBar, BorderSize, Mask, Enabled.
	BreezeExceptions []map[string]Value `yaml:"breeze-exceptions,omitempty"`
	// KWin window rules (kwinrulesrc). lodestar owns the whole file. Keys as
	// in kwinrulesrc: Description, wmclass, wmclassmatch, desktops, …
	WindowRules []map[string]Value `yaml:"window-rules,omitempty"`
	// Global shortcuts: a command (name, keys, run) or a KDE action
	// (component, action, keys).
	Shortcuts []Shortcut `yaml:"shortcuts,omitempty"`
	// Keys merged into JSON files that apps rewrite themselves.
	JSON []JSONMerge `yaml:"json,omitempty"`
	// Scripts run during apply, for what is not a file or a key.
	Hooks []Hook `yaml:"hooks,omitempty"`
	// The module's local package when its PKGBUILD lives in another repo, or
	// more folders whose changes rebuild the one in pkg/.
	Pkg *Pkg `yaml:"pkg,omitempty"`
}

// Firewall lists ports to open, as numbers or ranges (1714-1764).
type Firewall struct {
	TCP []Value `yaml:"tcp,omitempty"`
	UDP []Value `yaml:"udp,omitempty"`
}

// Shortcut is a global shortcut.
type Shortcut struct {
	// Name shown in System Settings, for a command.
	Name string `yaml:"name,omitempty"`
	// Command to run (sh syntax).
	Run string `yaml:"run,omitempty"`
	// KDE component of an existing action, e.g. kwin, plasmashell.
	Component string `yaml:"component,omitempty"`
	// The action's name in kglobalshortcutsrc, e.g. Window Maximize.
	Action string `yaml:"action,omitempty"`
	// One key, or a list: Meta+É, Ctrl+Alt+T. Empty to unbind an action.
	Keys StringList `yaml:"keys"`
}

// JSONMerge merges a JSON file of the module into a JSON file of $HOME.
type JSONMerge struct {
	// The file to change, e.g. ~/.config/app/settings.json.
	Path string `yaml:"path"`
	// The JSON file with the chosen keys, relative to the module folder.
	Merge string `yaml:"merge"`
	// Skip while this process runs (it would overwrite the file on exit).
	UnlessRunning string `yaml:"unless-running,omitempty"`
}

// Hook runs a script during apply.
type Hook struct {
	// A script in the module folder, or a command (sh syntax) run there.
	Run string `yaml:"run"`
	// user (default) or root.
	As string `yaml:"as,omitempty" jsonschema:"enum=user,enum=root"`
	// changed (default): when the module's folder changed since the last
	// run. always: on every apply.
	When string `yaml:"when,omitempty" jsonschema:"enum=changed,enum=always"`
}

// Pkg points to a PKGBUILD in another git repo, or adds folders to watch.
type Pkg struct {
	// Repo URL, or a local checkout (~/git/tool) while working on the tool.
	Git string `yaml:"git,omitempty"`
	// Tag or commit (fixed), or branch (followed).
	Ref string `yaml:"ref,omitempty"`
	// Folder of the PKGBUILD in that repo.
	Path string `yaml:"path,omitempty"`
	// More folders, relative to the module folder, whose changes rebuild
	// the package of pkg/ (its sources outside pkg/).
	Watch []string `yaml:"watch,omitempty"`
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
	// Boot loader settings.
	Boot *Boot `yaml:"boot,omitempty"`

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

// Boot holds the boot loader's settings.
type Boot struct {
	// The hand-written part of /boot/limine.conf (globals, extra entries),
	// relative to the host folder. limine-entry-tool writes the rest.
	Limine string `yaml:"limine,omitempty"`
}

// Mode is a file mode in octal. It keeps the text as written: YAML would read
// an unquoted 0644 as the number 420.
type Mode string

// UnmarshalYAML takes the scalar's source text, quoted or not.
func (m *Mode) UnmarshalYAML(raw []byte) error {
	*m = Mode(strings.Trim(strings.TrimSpace(string(raw)), `"'`))
	return nil
}

// Value is a scalar kept as written: KDE stores text, and YAML would turn an
// unquoted no into false or 0440 into 288.
type Value string

// UnmarshalYAML keeps a plain scalar's text; a quoted one is unquoted.
func (v *Value) UnmarshalYAML(raw []byte) error {
	text := strings.TrimSpace(string(raw))
	if strings.HasPrefix(text, `"`) || strings.HasPrefix(text, "'") {
		var s string
		if err := yaml.Unmarshal(raw, &s); err != nil {
			return err
		}
		*v = Value(s)
		return nil
	}
	if text == "~" || text == "null" {
		text = ""
	}
	*v = Value(text)
	return nil
}

// StringList is one string or a list of strings.
type StringList []string

// UnmarshalYAML accepts a scalar or a sequence.
func (l *StringList) UnmarshalYAML(raw []byte) error {
	var list []Value
	if err := yaml.Unmarshal(raw, &list); err == nil {
		*l = nil
		for _, v := range list {
			*l = append(*l, string(v))
		}
		return nil
	}
	var one Value
	if err := one.UnmarshalYAML(raw); err != nil {
		return err
	}
	*l = StringList{string(one)}
	return nil
}
