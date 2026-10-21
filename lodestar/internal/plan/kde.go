package plan

import (
	"fmt"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"github.com/romain-ncls/dotfiles/lodestar/internal/config"
	"github.com/romain-ncls/dotfiles/lodestar/internal/kconfig"
)

// The two KDE lists lodestar owns, by the file that holds them.
const (
	BreezeFile    = "breezerc"
	WindowRules   = "kwinrulesrc"
	breezeGroupRE = `^Windeco Exception [0-9]+$`
)

var breezeGroup = regexp.MustCompile(breezeGroupRE)

// shortcutFiles are the .desktop files of command shortcuts.
func shortcutFiles(c *config.Config) []*config.File {
	var out []*config.File
	for _, s := range c.Shortcuts {
		if s.Run == "" {
			continue
		}
		content := "[Desktop Entry]\n" +
			"Exec=" + desktopExec(s.Run) + "\n" +
			"Name=" + s.Name + "\n" +
			"NoDisplay=true\n" +
			"StartupNotify=false\n" +
			"Type=Application\n" +
			"X-KDE-GlobalAccel-CommandShortcut=true\n"
		out = append(out, &config.File{
			Target:    "~/.local/share/applications/" + s.DesktopFile(),
			Scope:     config.Home,
			Generated: []byte(content),
			From:      s.From,
		})
	}
	return out
}

// desktopExec writes a shell command for a .desktop Exec line: plain
// commands as they are, anything with shell syntax through sh -c.
func desktopExec(run string) string {
	run = strings.ReplaceAll(run, "%", "%%")
	if !strings.ContainsAny(run, "|&;<>()$`\\\"'*?[]#~=") {
		return run
	}
	return "sh -c '" + strings.ReplaceAll(run, "'", `'\''`) + "'"
}

// kdeFiles caches the parsed KDE files of the user's ~/.config.
type kdeFiles struct {
	dir   string
	files map[string]*kconfig.File
}

func (k *kdeFiles) get(name string) (*kconfig.File, error) {
	if f, ok := k.files[name]; ok {
		return f, nil
	}
	f, err := kconfig.Read(filepath.Join(k.dir, name))
	if err != nil {
		return nil, err
	}
	k.files[name] = f
	return f, nil
}

// kde plans KDE keys, shortcuts and the owned lists.
func (p *Plan) kde(in Input) error {
	c := in.Config
	files := &kdeFiles{dir: in.Root + filepath.Join(p.Home, ".config"), files: map[string]*kconfig.File{}}
	keys := slicesCloneKDE(c.KDE)

	// Command shortcuts: kglobalshortcutsrc [services][x.desktop] _launch.
	// KDE actions: [component] action = active,default,friendly name.
	for _, s := range c.Shortcuts {
		if s.Run != "" {
			keys = append(keys, config.KDEKey{File: "kglobalshortcutsrc", Group: []string{"services", s.DesktopFile()}, Key: "_launch", Value: strings.Join(s.Keys, "\t"), From: s.From})
			continue
		}
		f, err := files.get("kglobalshortcutsrc")
		if err != nil {
			return err
		}
		active := strings.Join(s.Keys, "\t")
		if active == "" {
			active = "none"
		}
		def, friendly := "none", s.Action
		if live, ok := f.Get([]string{s.Component}, s.Action); ok {
			parts := strings.SplitN(live, ",", 3)
			if len(parts) == 3 {
				if parts[0] == active {
					active = live // matches: keep the line as it is
				}
				def, friendly = parts[1], parts[2]
			}
		}
		value := active
		if !strings.Contains(active, ",") {
			value = active + "," + def + "," + friendly
		}
		keys = append(keys, config.KDEKey{File: "kglobalshortcutsrc", Group: []string{s.Component}, Key: s.Action, Value: value, From: s.From})
	}

	declared := map[string]bool{}
	var lookAndFeel string
	for _, k := range keys {
		id := k.ID()
		declared[id] = true
		f, err := files.get(k.File)
		if err != nil {
			return err
		}
		a := &Action{Op: OpKDE, Phase: PhaseHome, KDEFile: k.File, KDEGroup: k.Group, KDEKey: k.Key, KDEID: id, Value: k.Value, From: k.From}
		live, ok := f.Get(k.Group, k.Key)
		switch {
		case ok && live == k.Value:
			if rec, ok := in.HomeSt.KDE[id]; !ok || rec.Value != k.Value {
				a.Op, a.Why = OpAdopt, "already matches"
				p.add(a)
			}
			continue
		case ok:
			a.OldValue = &live
		}
		if k.File == "kdeglobals" && k.Key == "LookAndFeelPackage" && len(k.Group) == 1 && k.Group[0] == "KDE" {
			lookAndFeel = k.Value
		}
		p.add(a)
	}

	// Keys lodestar set that the repo dropped: back to KDE's default.
	ids := make([]string, 0, len(in.HomeSt.KDE))
	for id := range in.HomeSt.KDE {
		if !declared[id] {
			ids = append(ids, id)
		}
	}
	sort.Strings(ids)
	for _, id := range ids {
		rec := in.HomeSt.KDE[id]
		f, err := files.get(rec.File)
		if err != nil {
			return err
		}
		a := &Action{Phase: PhaseHome, KDEFile: rec.File, KDEGroup: rec.Group, KDEKey: rec.Key, KDEID: id}
		live, ok := f.Get(rec.Group, rec.Key)
		switch {
		case !ok:
			a.Op = OpForget
		case live != rec.Value:
			a.Op, a.Why = OpForget, "no longer declared, but changed on the machine: left as it is"
		default:
			a.Op, a.Delete, a.OldValue, a.Why = OpKDE, true, &live, "no longer declared: KDE's default comes back"
		}
		p.add(a)
	}

	if err := p.kdeList(in, files, BreezeFile, "breeze", c.BreezeExceptions); err != nil {
		return err
	}
	if err := p.kdeList(in, files, WindowRules, "kwinrules", c.WindowRules); err != nil {
		return err
	}

	p.kdeFollowUps(lookAndFeel)
	return nil
}

func slicesCloneKDE(k []config.KDEKey) []config.KDEKey { return append([]config.KDEKey(nil), k...) }

// ListEntries reads the live entries of a list.
func ListEntries(f *kconfig.File, list string) []map[string]string {
	var out []map[string]string
	switch list {
	case "breeze":
		type numbered struct {
			n    int
			keys map[string]string
		}
		var groups []numbered
		for _, g := range f.Groups {
			if len(g.Path) == 1 && breezeGroup.MatchString(g.Path[0]) {
				n, _ := strconv.Atoi(strings.TrimPrefix(g.Path[0], "Windeco Exception "))
				groups = append(groups, numbered{n, g.Map()})
			}
		}
		sort.Slice(groups, func(i, j int) bool { return groups[i].n < groups[j].n })
		for _, g := range groups {
			out = append(out, g.keys)
		}
	case "kwinrules":
		order, _ := f.Get([]string{"General"}, "Order")
		for _, name := range strings.Split(order, ",") {
			if g := f.Group([]string{name}); g != nil && name != "" {
				out = append(out, g.Map())
			}
		}
	}
	return out
}

// kdeList plans one owned list: lodestar writes it whole when it is declared,
// and empties it when the repo drops a list lodestar owned.
func (p *Plan) kdeList(in Input, files *kdeFiles, file, list string, entries []config.KDEEntry) error {
	if len(entries) == 0 && !in.HomeSt.OwnsList(file) {
		return nil
	}
	f, err := files.get(file)
	if err != nil {
		return err
	}
	want := make([]map[string]string, 0, len(entries))
	var from []string
	for _, e := range entries {
		want = append(want, e.Keys)
		if len(from) == 0 || from[len(from)-1] != e.From {
			from = append(from, e.From)
		}
	}
	live := ListEntries(f, list)
	if listText(live) == listText(want) {
		if len(entries) > 0 && !in.HomeSt.OwnsList(file) {
			p.add(&Action{Op: OpAdopt, Phase: PhaseHome, KDEFile: file, List: list, Entries: want, Why: "already matches"})
		}
		return nil
	}
	a := &Action{Op: OpKDEList, Phase: PhaseHome, KDEFile: file, List: list, Entries: want, From: strings.Join(from, ", "),
		Display: fmt.Sprintf("%s: %d entries", file, len(want)), Content: []byte(listText(want)), Old: []byte(listText(live))}
	switch {
	case len(want) == 0:
		a.Why = "no longer declared: the list is emptied"
	case len(live) == 0:
		a.Why = "new"
	default:
		a.Why = "differs"
	}
	p.add(a)
	return nil
}

// listText shows a list as text, for comparing and for the diff.
func listText(entries []map[string]string) string {
	var sb strings.Builder
	for i, e := range entries {
		fmt.Fprintf(&sb, "[%d]\n", i+1)
		keys := make([]string, 0, len(e))
		for k := range e {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		for _, k := range keys {
			fmt.Fprintf(&sb, "%s=%s\n", k, e[k])
		}
	}
	return sb.String()
}

// kdeFollowUps makes a running Plasma pick the changes up.
func (p *Plan) kdeFollowUps(lookAndFeel string) {
	touched := map[string]bool{}
	desktop := false
	for _, a := range p.Actions {
		if a.Phase != PhaseHome {
			continue
		}
		if (a.Op == OpKDE || a.Op == OpKDEList) && a.KDEFile != "" {
			touched[a.KDEFile] = true
		}
		if strings.HasPrefix(a.Display, "~/.local/share/applications/") && a.Op != OpAdopt && a.Op != OpForget {
			desktop = true
		}
	}
	if lookAndFeel != "" {
		// The global theme sets colours, icons and more; the declared keys
		// are written after it, so they win.
		run := &Action{Op: OpRun, Phase: PhaseHome, Why: "global theme",
			Command: `[ -z "$WAYLAND_DISPLAY" ] || plasma-apply-lookandfeel --apply ` + shellQuote(lookAndFeel)}
		for i, a := range p.Actions {
			if a.Op == OpKDE {
				p.Actions = append(p.Actions[:i], append([]*Action{run}, p.Actions[i:]...)...)
				break
			}
		}
	}
	if touched["kwinrc"] || touched["kdeglobals"] || touched[BreezeFile] || touched[WindowRules] {
		p.add(&Action{Op: OpRun, Phase: PhaseHome, Why: "KWin reads its settings again",
			Command: "busctl --user call org.kde.KWin /KWin org.kde.KWin reconfigure >/dev/null 2>&1 || true"})
	}
	if touched["kglobalshortcutsrc"] || desktop {
		p.add(&Action{Op: OpRun, Phase: PhaseHome, Why: "shortcuts are read again",
			Command: "kbuildsycoca6 >/dev/null 2>&1; systemctl --user try-restart plasma-kglobalaccel.service 2>/dev/null || true"})
	}
}

func shellQuote(s string) string { return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'" }
